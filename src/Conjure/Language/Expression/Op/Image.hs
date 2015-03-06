{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.Expression.Op.Image where

import Conjure.Prelude
import Conjure.Language.Expression.Op.Internal.Common


data OpImage x = OpImage x x
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpImage x)
instance Hashable  x => Hashable  (OpImage x)
instance ToJSON    x => ToJSON    (OpImage x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpImage x) where parseJSON = genericParseJSON jsonOptions

instance (TypeOf x, Pretty x) => TypeOf (OpImage x) where
    typeOf p@(OpImage f x) = do
        tyF <- typeOf f
        (from, to) <- case tyF of
            TypeFunction from to -> return (from, to)
            TypeSequence      to -> return (TypeInt, to)
            _ -> raiseTypeError p
        xTy <- typeOf x
        if typesUnify [xTy, from]
            then return to
            else raiseTypeError $ vcat
                [ pretty p
                , "f     :" <+> pretty f
                , "f type:" <+> pretty (TypeFunction from to)
                , "x     :" <+> pretty x
                , "x type:" <+> pretty xTy
                ]

instance Pretty x => DomainOf (OpImage x) x where
    domainOf op = na $ "evaluateOp{OpImage}:" <++> pretty op

instance EvaluateOp OpImage where
    evaluateOp (OpImage f@(ConstantAbstract (AbsLitFunction xs)) a) = do
        TypeFunction _ tyTo <- typeOf f
        case [ y | (x,y) <- xs, a == x ] of
            [y] -> return y
            []  -> return $ mkUndef tyTo $ vcat
                    [ "Function is not defined at this point:" <+> pretty a
                    , "Function value:" <+> pretty (ConstantAbstract (AbsLitFunction xs))
                    ]
            _   -> return $ mkUndef tyTo $ vcat
                    [ "Function is multiply defined at this point:" <+> pretty a
                    , "Function value:" <+> pretty (ConstantAbstract (AbsLitFunction xs))
                    ]
    evaluateOp (OpImage f@(ConstantAbstract (AbsLitSequence xs)) a) = do
        TypeSequence tyTo <- typeOf f
        case [ y | (x,y) <- zip allNats xs, a == fromInt x ] of
            [y] -> return y
            []  -> return $ mkUndef tyTo $ vcat
                    [ "Sequence is not defined at this point:" <+> pretty a
                    , "Sequence value:" <+> pretty (ConstantAbstract (AbsLitSequence xs))
                    ]
            _   -> return $ mkUndef tyTo $ vcat
                    [ "Sequence is multiply defined at this point:" <+> pretty a
                    , "Sequence value:" <+> pretty (ConstantAbstract (AbsLitSequence xs))
                    ]
    evaluateOp op = na $ "evaluateOp{OpImage}:" <++> pretty (show op)

instance SimplifyOp OpImage x where
    simplifyOp _ = na "simplifyOp{OpImage}"

instance Pretty x => Pretty (OpImage x) where
    prettyPrec _ (OpImage a b) = "image" <> prettyList prParens "," [a,b]