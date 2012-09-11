{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ViewPatterns #-}

module Language.E.Evaluator.Full where

import Language.E.Definition
import Language.E.DomainOf
import Language.E.MatchBind
import Language.E.TH
import Language.E.TypeOf


fullEvaluator :: Monad m => E -> CompE m (Maybe E)
fullEvaluator [xMatch| [Prim (S "+")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] = returnInt $ a + b
fullEvaluator [xMatch| [Prim (S "-")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] = returnInt $ a - b
fullEvaluator [xMatch| [Prim (S "*")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] = returnInt $ a * b
fullEvaluator [xMatch| [Prim (S "/")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] | b > 0 = returnInt $ a `div` b
fullEvaluator [xMatch| [Prim (S "%")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] | b > 0 = returnInt $ a `mod` b

fullEvaluator [eMatch| !false |] = ret [eMake| true  |]
fullEvaluator [eMatch| !true  |] = ret [eMake| false |]

fullEvaluator [eMatch| toInt(false) |] = ret [eMake| 0 |]
fullEvaluator [eMatch| toInt(true)  |] = ret [eMake| 1 |]

fullEvaluator [xMatch| [Prim (S "=")] := binOp.operator
                     | [Prim x] := binOp.left .value.literal
                     | [Prim y] := binOp.right.value.literal
                     |]
                     | x == y
                     = ret [eMake| true |]

fullEvaluator [xMatch| [Prim (S "/\\")] := binOp.operator
                     | [ ] := binOp.left.emptyGuard
                     | [x] := binOp.right
                     |] = ret x

fullEvaluator [xMatch| [Prim (S "/\\")] := binOp.operator
                     | [x] := binOp.left
                     | [ ] := binOp.right.emptyGuard
                     |] = ret x


fullEvaluator _ = return Nothing


returnBool :: Monad m => Bool -> CompE m (Maybe E)
returnBool i = ret [xMake| value.literal := [Prim (B i)] |]

returnInt :: Monad m => Integer -> CompE m (Maybe E)
returnInt i = ret [xMake| value.literal := [Prim (I i)] |]

ret :: Monad m => E -> CompE m (Maybe E)
ret = return . Just


evalHasType :: Monad m => E -> CompE m (Maybe E)
evalHasType _p@[eMatch| &s hastype &dom |] = do
    -- mkLog "evalHasType1" $ pretty p
    ts <- typeOf s
    -- mkLog "evalHasType2" $ pretty p
    td <- typeOf dom
    -- mkLog "evalHasType3" $ pretty p
    b  <- typeUnify ts td
    -- mkLog "evalHasType4" $ pretty p
    returnBool b
evalHasType _ = return Nothing

evalHasDomain :: Monad m => E -> CompE m (Maybe E)
evalHasDomain _p@[eMatch| &x hasdomain &y |] = do
    -- mkLog "evalHasDomain" $ pretty p
    dx <- domainOf x
    dy <- domainOf y
    -- mkLog "debug:evalHasDomain" $ pretty dx
    -- mkLog "debug:evalHasDomain" $ prettyAsPaths dx
    -- mkLog "debug:evalHasDomain" $ pretty dy
    b  <- patternMatch dy dx
    returnBool b
evalHasDomain _ = return Nothing
