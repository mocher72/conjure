{-# LANGUAGE FlexibleContexts #-}

module Main where


import Control.Applicative
import Control.Exception ( SomeException, try )
import Control.Monad ( when )
import Control.Monad.IO.Class ( MonadIO, liftIO )
import Control.Monad.State ( MonadState, get, gets, put )
import Control.Monad.Trans.State.Lazy ( StateT, evalStateT )
import Data.Char ( toLower )
import Data.List ( intercalate, isPrefixOf )
import Data.Maybe ( fromJust )
import System.Console.Readline ( addHistory, readline )
import System.Environment ( getArgs )

import Language.Essence ( Spec(..), Log )
import Language.EssenceEvaluator ( runEvaluateExpr )
import Language.EssenceKinds ( runKindOf )
import Language.EssenceParsers ( pSpec, pExpr, pTopLevels, pObjective )
import Language.EssencePrinters ( prSpec, prExpr, prType, prKind )
import Language.EssenceTypes ( runTypeOf )
import ParsecUtils ( Parser, parseEither, parseFromFile, eof, choiceTry )
import PrintUtils ( Doc, render )
import Utils ( ppPrint, strip )


data Command = EvalTypeKind String
             | Eval String
             | TypeOf String
             | KindOf String
             | Load FilePath
             | Save FilePath
             | Record String        -- might record a declaration, where clause, objective, or constraint
             | RmDeclaration String
             | RmConstraint String
             | RmObjective
             | Rollback
             | DisplaySpec
             | Quit
             | Flag String
    deriving (Eq, Ord, Read, Show)


-- given the input line, returns either an error message or Command to be
-- excuted.
parseCommand :: String -> Either String Command
parseCommand s = do
    case strip s of
        (':':ss) -> do
            firstWord <- case words ss of []    -> Right ""
                                          (i:_) -> Right $ map toLower i
            let restOfLine = strip $ drop (length firstWord) ss
            let actions = [ ( "evaluate"      , Eval restOfLine          )
                          , ( "typeof"        , TypeOf restOfLine        )
                          , ( "kindof"        , KindOf restOfLine        )
                          , ( "load"          , Load restOfLine          )
                          , ( "save"          , Save restOfLine          )
                          , ( "record"        , Record restOfLine        )
                          , ( "rmdeclaration" , RmDeclaration restOfLine )
                          , ( "rmconstraint"  , RmConstraint restOfLine  )
                          , ( "rmobjective"   , RmObjective              )
                          , ( "rollback"      , Rollback                 )
                          , ( "displayspec"   , DisplaySpec              )
                          , ( "quit"          , Quit                     )
                          , ( "flag"          , Flag restOfLine          )
                          ]
            case filter (\ (i,_) -> isPrefixOf firstWord i ) actions of
                []        -> Left "no such action"
                [(_,act)] -> Right act
                xs        -> Left $ "ambigious: " ++ intercalate ", " (map fst xs) ++ "?"
        line -> Right $ EvalTypeKind line


data REPLState = REPLState { currentSpec   :: Spec
                           , oldSpecs      :: [Spec]
                           , commandHist   :: [Command]
                           , flagLogs      :: Bool
                           , flagRawOutput :: Bool
                           }
    deriving (Eq, Ord, Read, Show)


initREPLState :: REPLState
initREPLState = REPLState { currentSpec   = sp
                          , oldSpecs      = []
                          , commandHist   = []
                          , flagLogs      = False
                          , flagRawOutput = False
                          }
    where
        sp :: Spec
        sp = Spec { language         = "Essence"
                  , version          = [2,0]
                  , topLevelBindings = []
                  , topLevelWheres   = []
                  , objective        = Nothing
                  , constraints      = []
                  }

modifySpec :: MonadState REPLState m => (Spec -> Spec) -> m ()
modifySpec f = do
    st <- get
    let sp  = currentSpec st
    let sp' = f sp
    put st { currentSpec = sp'
           , oldSpecs    = sp : oldSpecs st
           }


returningTrue :: Applicative f => f () -> f Bool
returningTrue f = pure True <* f

withParsed :: (Applicative m, MonadIO m) => Parser a -> String -> (a -> m ()) -> m Bool
withParsed p s comp = returningTrue $ case parseEither (p <* eof) s of
    Left msg -> liftIO $ putStrLn msg
    Right x  -> comp x

prettyPrint :: (MonadIO m, Show a) => (a -> Maybe Doc) -> a -> m ()
prettyPrint f x = case f x of
    Nothing  -> liftIO $ putStrLn $ "Error while printing this: " ++ show x
    Just doc -> liftIO $ putStrLn $ render doc

displayLogs :: (MonadIO m, MonadState REPLState m) => [Log] -> m ()
displayLogs logs = do
    flag <- gets flagLogs
    when flag $ liftIO $ putStrLn $ unlines $ "[LOGS]" : map ("  "++) logs

displayRaws :: (MonadIO m, MonadState REPLState m, Show a, Show b) => a -> b -> m ()
displayRaws x y = do
    flag <- gets flagRawOutput
    when flag $ do
        liftIO $ ppPrint x
        liftIO $ ppPrint y


step :: Command -> StateT REPLState IO Bool
step (EvalTypeKind s) = step (KindOf s) >> step (TypeOf s) >> step (Eval s)
step (Eval s) = withParsed pExpr s $ \ x -> do
    bs <- gets $ topLevelBindings . currentSpec
    let (x', logs) = runEvaluateExpr bs x
    displayLogs logs
    displayRaws x x'
    prettyPrint prExpr x'
step (TypeOf s) = withParsed pExpr s $ \ x -> do
    bs <- gets $ topLevelBindings . currentSpec
    let (et, logs) = runTypeOf bs x
    displayRaws x et
    case et of
        Left err -> liftIO $ putStrLn $ "Error while type-checking: " ++ err
        Right t  -> do
            displayLogs logs
            prettyPrint prType t
step (KindOf s) = withParsed pExpr s $ \ x -> do
    bs <- gets $ topLevelBindings . currentSpec
    let (ek, logs) = runKindOf bs x
    displayRaws x ek
    case ek of
        Left err -> liftIO $ putStrLn $ "Error while kind-checking: " ++ err
        Right k  -> do
            displayLogs logs
            prettyPrint prKind k
step (Load fp) = returningTrue $ do
    esp <- liftIO readIt
    case esp of
        Left e   -> liftIO $ putStrLn $ "IO Error: " ++ show e
        Right sp -> modifySpec $ \ _ -> sp
    where
        readIt :: IO (Either SomeException Spec)
        readIt = try $ parseFromFile pSpec id fp id
step (Save fp) = returningTrue $ do
    sp <- gets currentSpec
    case prSpec sp of
        Nothing  -> liftIO $ putStrLn "Error while rendering the current specification."
        Just doc -> liftIO $ writeFile fp $ render doc

step (Record s) = withParsed (choiceTry [ Left . Right <$> pObjective
                                        , Right        <$> pExpr
                                        , Left . Left  <$> pTopLevels
                                        ]) s $ \ res -> case res of
    Left (Left (bs,ws)) -> modifySpec $ \ sp -> sp { topLevelBindings = topLevelBindings sp ++ bs
                                                   , topLevelWheres   = topLevelWheres   sp ++ ws
                                                   }
    Left (Right o)      -> modifySpec $ \ sp -> sp { objective = Just o }
    Right x             -> modifySpec $ \ sp -> sp { constraints = constraints sp ++ [x] }

step (RmDeclaration _) = returningTrue $ liftIO $ putStrLn "not implemented, yet."
step (RmConstraint  _) = returningTrue $ liftIO $ putStrLn "not implemented, yet."
step RmObjective       = returningTrue $ modifySpec $ \ sp -> sp { objective = Nothing }

step Rollback = returningTrue $ do
    st <- get
    let olds = oldSpecs st
    case olds of
        []     -> return ()
        (s:ss) -> put st { currentSpec = s, oldSpecs = ss }
step DisplaySpec = returningTrue $ do
    sp <- gets currentSpec
    prettyPrint prSpec sp
step (Flag nm) = returningTrue $ stepFlag nm
step Quit = return False


stepFlag :: (MonadIO m, MonadState REPLState m) => String -> m ()
stepFlag "rawOutput" = do
    st  <- get
    val <- gets flagRawOutput
    put $ st { flagRawOutput = not val }
stepFlag "logging" = do
    st  <- get
    val <- gets flagLogs
    put $ st { flagLogs = not val }
stepFlag flag = liftIO $ putStrLn $ "no such flag: " ++ flag


main :: IO ()
main = do
    args <- getArgs
    case args of
        []   -> evalStateT repl initREPLState
        [fp] -> do
            putStrLn ("Loading from: " ++ fp)
            evalStateT (step (Load fp) >> repl) initREPLState
        _    -> do
            putStrLn $ unlines [ "This program accepts 1 optional argument,"
                               , "which must be a file path pointing to an Essence specification."
                               , ""
                               , "You've given several arguments."
                               ]
    where
        repl :: StateT REPLState IO ()
        repl = do
            maybeLine <- liftIO $ readline "# "
            case (maybeLine, parseCommand (fromJust maybeLine)) of
                (Nothing  , _            ) -> return () -- EOF / control-d
                (Just ""  , _            ) -> repl
                (Just line, Left msg     ) -> do liftIO $ addHistory line
                                                 liftIO $ putStrLn msg
                                                 repl
                (Just line, Right command) -> do liftIO $ addHistory line
                                                 c <- step command
                                                 when c repl
