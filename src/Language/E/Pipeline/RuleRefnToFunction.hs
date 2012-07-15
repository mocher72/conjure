{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE QuasiQuotes #-}

module Language.E.Pipeline.RuleRefnToFunction ( ruleRefnToFunction ) where

import Language.E
import Language.E.Pipeline.FreshNames

import qualified Data.Set as S


-- does the grouping depending on levels and such.
-- for a description on the params and return type see combineRuleRefns
ruleRefnToFunction :: (Functor m, Monad m)
    => [RuleRefn]
    -> Either
        [CompError]
        [E -> CompE m (Maybe [(String, E)])]
ruleRefnToFunction fs =
    let
        justsFirst :: Ord a => Maybe a -> Maybe a -> Ordering
        justsFirst (Just i) (Just j) = compare i j
        justsFirst Nothing (Just _)  = GT
        justsFirst (Just _) Nothing  = LT
        justsFirst Nothing  Nothing  = EQ

        fsGrouped :: [[RuleRefn]]
        fsGrouped = groupBy (\ (_,a,_) (_,b,_) -> a == b )
                  $ sortBy  (\ (_,a,_) (_,b,_) -> justsFirst a b )
                    fs

        -- mresults :: (Functor m, Monad m) => [Either [CompError] (E -> CompE m E)]
        mresults = map combineRuleRefns fsGrouped

        -- errors :: [CompError]
        errors = concat $ lefts mresults

        -- funcs :: (Functor m, Monad m) => [E -> CompE m E]
        funcs = rights mresults
    in
        if null errors
            then Right funcs
            else Left  errors


combineRuleRefns :: (Functor m, Monad m)
    => [RuleRefn]                                       -- given a list of RuleRefns
    -> Either                                           -- return
        [CompError]                                     -- either a list of errors (due to static checking a RuleRefn)
        (E -> CompE m (Maybe [(String, E)]))            -- or a (Just list) of functions. the return type contains the rule name in the string.
                                                        --    a Nothing means no rule applications at that level.
combineRuleRefns fs =
    let
        -- mresults :: (Functor m, Monad m) => [Either CompError (E -> CompE m (Maybe E))]
        mresults = map single fs

        -- errors   :: [CompError]
        errors   = lefts  mresults

        -- funcs    :: (Functor m, Monad m) => [E -> CompE m (Maybe E)]
        funcs    = rights mresults
    in  if null errors
            then Right $ \ x -> do
                mys <- mapM ($ x) funcs
                let ys = catMaybes mys
                if null ys
                    then return Nothing
                    else return (Just ys)
            else Left errors


single :: forall m . (Functor m, Monad m)
    => RuleRefn
    -> Either
        CompError                                       -- static errors in the rule
        (E -> CompE m (Maybe (String, E)))                 -- the rule as a function.
single ( name
       , _
       , [xMatch| [pattern] := rulerefn.pattern
                | templates := rulerefn.templates
                | locals    := rulerefn.locals
                |]
       ) = do
    let
        staticCheck :: Either CompError ()
        staticCheck = do
            let metaVarsIn p = S.fromList [ r | [xMatch| [Prim (S r)] := metavar |] <- universe p ]
            let patternMetaVars   = metaVarsIn pattern
            let templateMetaVars  = S.unions [ metaVarsIn template
                                             | template <- templates ]
            let hasDomainMetaVars = S.unions [ S.unions [ metaVarsIn b
                                                        | [xMatch| [Prim (S "hasdomain")] := binOp.operator
                                                                 | [b] := binOp.right
                                                                 |] <- universe loc
                                                        ]
                                             | loc <- locals
                                             ]
            unless (templateMetaVars `S.isSubsetOf` S.unions [patternMetaVars,hasDomainMetaVars])
                $ Left ( ErrFatal
                       , vcat [ "Pattern meta variables:"  <+> prettyListDoc id "," (map stringToDoc $ S.toList patternMetaVars)
                              , "Template meta variables:" <+> prettyListDoc id "," (map stringToDoc $ S.toList templateMetaVars)
                              ]
                       )
    staticCheck

    return $ \ x -> do
        bindersBefore <- gets binders
        let restoreState = modify $ \ st -> st { binders = bindersBefore }
        flagMatch <- patternMatch pattern x
        let
            localHandler :: E -> CompE m Bool
            localHandler lokal@[xMatch| [y] := topLevel.where |] = do
                xBool <- toBool y
                case xBool of
                    Just True  -> return True
                    Just False -> do
                        mkLog "rule-fail"
                            $ "where statement evaluated to false: " <++> vcat [ pretty lokal
                                                                               , "in rule" <+> stringToDoc name
                                                                               , "at expression" <+> pretty x
                                                                               ]
                        return False
                    Nothing    -> do
                        mkLog "rule-fail"
                            $ "where statement cannot be fully evaluated: " <++> vcat [ pretty lokal
                                                                                      , "in rule" <+> stringToDoc name
                                                                                      , "at expression" <+> pretty x
                                                                                      ]
                        return False
            localHandler lokal = throwError ( ErrFatal, "not handled" <+> prettyAsTree lokal )
        if flagMatch
            then do
                bs        <- mapM localHandler locals
                if and bs
                    then do
                        template  <- returns templates
                        template' <- freshNames template
                        mres      <- runMaybeT $ patternBind template'
                        case mres of
                            Nothing  -> restoreState >> errRuleFail
                            Just res -> restoreState >> return (Just (name, res))
                    else restoreState >> errRuleFail
            else restoreState >> errRuleFail
single _ = Left (ErrFatal, "This should never happen. (in RuleRefnToFunction.worker)")


errRuleFail :: Monad m => CompE m (Maybe a)
errRuleFail = return Nothing
