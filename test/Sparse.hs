{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE UndecidableInstances       #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Sparse
  ( testSuite
  , ShortPoly(..)
  ) where

import Prelude hiding (gcd, quotRem, rem)
import Data.Euclidean (Euclidean(..), GcdDomain(..))
import Data.Function
import Data.Int
import Data.List (groupBy, sortOn)
import Data.Mod
import Data.Poly.Sparse
import qualified Data.Poly.Sparse.Semiring as S
import Data.Proxy
import Data.Semiring (Semiring)
import qualified Data.Vector as V
import qualified Data.Vector.Generic as G
import qualified Data.Vector.Unboxed as U
import Test.Tasty
import Test.Tasty.QuickCheck hiding (scale, numTests)

import Quaternion
import TestUtils

instance (Eq a, Semiring a, Arbitrary a, G.Vector v (Word, a)) => Arbitrary (Poly v a) where
  arbitrary = S.toPoly . G.fromList <$> arbitrary
  shrink = fmap (S.toPoly . G.fromList) . shrink . G.toList . unPoly

newtype ShortPoly a = ShortPoly { unShortPoly :: a }
  deriving (Eq, Show, Semiring, GcdDomain, Euclidean)

instance (Eq a, Semiring a, Arbitrary a, G.Vector v (Word, a)) => Arbitrary (ShortPoly (Poly v a)) where
  arbitrary = ShortPoly . S.toPoly . G.fromList . (\xs -> take (length xs `mod` 5) xs) <$> arbitrary
  shrink = fmap (ShortPoly . S.toPoly . G.fromList) . shrink . G.toList . unPoly . unShortPoly

testSuite :: TestTree
testSuite = testGroup "Sparse"
    [ arithmeticTests
    , otherTests
    , lawsTests
    , evalTests
    , derivTests
    ]

lawsTests :: TestTree
lawsTests = testGroup "Laws"
  $ semiringTests ++ ringTests ++ numTests ++ euclideanTests ++ gcdDomainTests ++ isListTests ++ showTests

semiringTests :: [TestTree]
semiringTests =
  [ mySemiringLaws (Proxy :: Proxy (Poly U.Vector ()))
  , mySemiringLaws (Proxy :: Proxy (Poly U.Vector Int8))
  , mySemiringLaws (Proxy :: Proxy (Poly V.Vector Integer))
  , tenTimesLess
  $ mySemiringLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

ringTests :: [TestTree]
ringTests =
  [ myRingLaws (Proxy :: Proxy (Poly U.Vector ()))
  , myRingLaws (Proxy :: Proxy (Poly U.Vector Int8))
  , myRingLaws (Proxy :: Proxy (Poly V.Vector Integer))
  , myRingLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

numTests :: [TestTree]
numTests =
  [ myNumLaws (Proxy :: Proxy (Poly U.Vector Int8))
  , myNumLaws (Proxy :: Proxy (Poly V.Vector Integer))
  , tenTimesLess
  $ myNumLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

gcdDomainTests :: [TestTree]
gcdDomainTests =
  [ myGcdDomainLaws (Proxy :: Proxy (ShortPoly (Poly V.Vector Integer)))
  , tenTimesLess
  $ myGcdDomainLaws (Proxy :: Proxy (ShortPoly (Poly V.Vector (Mod 3))))
  , tenTimesLess
  $ myGcdDomainLaws (Proxy :: Proxy (ShortPoly (Poly V.Vector Rational)))
  ]

euclideanTests :: [TestTree]
euclideanTests =
  [ myEuclideanLaws (Proxy :: Proxy (ShortPoly (Poly V.Vector (Mod 3))))
  , myEuclideanLaws (Proxy :: Proxy (ShortPoly (Poly V.Vector Rational)))
  ]

isListTests :: [TestTree]
isListTests =
  [ myIsListLaws (Proxy :: Proxy (Poly U.Vector ()))
  , myIsListLaws (Proxy :: Proxy (Poly U.Vector Int8))
  , myIsListLaws (Proxy :: Proxy (Poly V.Vector Integer))
  , tenTimesLess
  $ myIsListLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

showTests :: [TestTree]
showTests =
  [ myShowLaws (Proxy :: Proxy (Poly U.Vector ()))
  , myShowLaws (Proxy :: Proxy (Poly U.Vector Int8))
  , myShowLaws (Proxy :: Proxy (Poly V.Vector Integer))
  , tenTimesLess
  $ myShowLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

arithmeticTests :: TestTree
arithmeticTests = testGroup "Arithmetic"
  [ testProperty "addition matches reference" $
    \(xs :: [(Word, Int)]) ys -> toPoly (V.fromList (addRef xs ys)) ===
      toPoly (V.fromList xs) + toPoly (V.fromList ys)
  , testProperty "subtraction matches reference" $
    \(xs :: [(Word, Int)]) ys -> toPoly (V.fromList (subRef xs ys)) ===
      toPoly (V.fromList xs) - toPoly (V.fromList ys)
  , tenTimesLess $
    testProperty "multiplication matches reference" $
    \(xs :: [(Word, Int)]) ys -> toPoly (V.fromList (mulRef xs ys)) ===
      toPoly (V.fromList xs) * toPoly (V.fromList ys)
  ]

addRef :: Num a => [(Word, a)] -> [(Word, a)] -> [(Word, a)]
addRef [] ys = ys
addRef xs [] = xs
addRef xs@((xp, xc) : xs') ys@((yp, yc) : ys') =
  case xp `compare` yp of
    LT -> (xp, xc) : addRef xs' ys
    EQ -> (xp, xc + yc) : addRef xs' ys'
    GT -> (yp, yc) : addRef xs ys'

subRef :: Num a => [(Word, a)] -> [(Word, a)] -> [(Word, a)]
subRef [] ys = map (fmap negate) ys
subRef xs [] = xs
subRef xs@((xp, xc) : xs') ys@((yp, yc) : ys') =
  case xp `compare` yp of
    LT -> (xp, xc) : subRef xs' ys
    EQ -> (xp, xc - yc) : subRef xs' ys'
    GT -> (yp, negate yc) : subRef xs ys'

mulRef :: Num a => [(Word, a)] -> [(Word, a)] -> [(Word, a)]
mulRef xs ys
  = map (\ws -> (fst (head ws), sum (map snd ws)))
  $ groupBy ((==) `on` fst)
  $ sortOn fst
  $ [ (xp + yp, xc * yc) | (xp, xc) <- xs, (yp, yc) <- ys ]

otherTests :: TestTree
otherTests = testGroup "other" $ concat
  [ otherTestGroup (Proxy :: Proxy Int8)
  , otherTestGroup (Proxy :: Proxy (Quaternion Int))
  ]

otherTestGroup
  :: forall a.
     (Eq a, Show a, Semiring a, Num a, Arbitrary a, U.Unbox a, G.Vector U.Vector a)
  => Proxy a
  -> [TestTree]
otherTestGroup _ =
  [ testProperty "leading p 0 == Nothing" $
    \p -> leading (monomial p 0 :: UPoly a) === Nothing
  , testProperty "leading . monomial = id" $
    \p c -> c /= 0 ==> leading (monomial p c :: UPoly a) === Just (p, c)
  , testProperty "monomial matches reference" $
    \p (c :: a) -> monomial p c === toPoly (V.fromList (monomialRef p c))
  , tenTimesLess $
    testProperty "scale matches multiplication by monomial" $
    \p c (xs :: UPoly a) -> scale p c xs === monomial p c * xs
  ]

monomialRef :: Num a => Word -> a -> [(Word, a)]
monomialRef p c = [(p, c)]

evalTests :: TestTree
evalTests = testGroup "eval" $ concat
  [ evalTestGroup  (Proxy :: Proxy (Poly U.Vector Int8))
  , evalTestGroup  (Proxy :: Proxy (Poly V.Vector Integer))
  , substTestGroup (Proxy :: Proxy (Poly U.Vector Int8))
  ]

evalTestGroup
  :: forall v a.
     (Eq a, Num a, Semiring a, Arbitrary a, Show a, Eq (v (Word, a)), Show (v (Word, a)), G.Vector v (Word, a))
  => Proxy (Poly v a)
  -> [TestTree]
evalTestGroup _ =
  [ testProperty "eval (p + q) r = eval p r + eval q r" $
    \p q r -> e (p + q) r === e p r + e q r
  , testProperty "eval (p * q) r = eval p r * eval q r" $
    \p q r -> e (p * q) r === e p r * e q r
  , testProperty "eval x p = p" $
    \p -> e X p === p
  , testProperty "eval (monomial 0 c) p = c" $
    \c p -> e (monomial 0 c) p === c

  , testProperty "eval' (p + q) r = eval' p r + eval' q r" $
    \p q r -> e' (p + q) r === e' p r + e' q r
  , testProperty "eval' (p * q) r = eval' p r * eval' q r" $
    \p q r -> e' (p * q) r === e' p r * e' q r
  , testProperty "eval' x p = p" $
    \p -> e' S.X p === p
  , testProperty "eval' (S.monomial 0 c) p = c" $
    \c p -> e' (S.monomial 0 c) p === c
  ]

  where
    e :: Poly v a -> a -> a
    e = eval
    e' :: Poly v a -> a -> a
    e' = S.eval

substTestGroup
  :: forall v a.
     (Eq a, Num a, Semiring a, Arbitrary a, Show a, Eq (v (Word, a)), Show (v (Word, a)), G.Vector v (Word, a))
  => Proxy (Poly v a)
  -> [TestTree]
substTestGroup _ =
  [ testProperty "subst x p = p" $
    \p -> e X p === p
  , testProperty "subst (monomial 0 c) p = monomial 0 c" $
    \c p -> e (monomial 0 c) p === monomial 0 c
  , testProperty "subst' x p = p" $
    \p -> e' S.X p === p
  , testProperty "subst' (S.monomial 0 c) p = S.monomial 0 c" $
    \c p -> e' (S.monomial 0 c) p === S.monomial 0 c
  ]
  where
    e :: Poly v a -> Poly v a -> Poly v a
    e = subst
    e' :: Poly v a -> Poly v a -> Poly v a
    e' = S.subst

derivTests :: TestTree
derivTests = testGroup "deriv"
  [ testProperty "deriv = S.deriv" $
    \(p :: Poly V.Vector Integer) -> deriv p === S.deriv p
  , testProperty "integral = S.integral" $
    \(p :: Poly V.Vector Rational) -> integral p === S.integral p
  , testProperty "deriv . integral = id" $
    \(p :: Poly V.Vector Rational) -> deriv (integral p) === p
  , testProperty "deriv c = 0" $
    \c -> deriv (monomial 0 c :: Poly V.Vector Int) === 0
  , testProperty "deriv cX = c" $
    \c -> deriv (monomial 0 c * X :: Poly V.Vector Int) === monomial 0 c
  , testProperty "deriv (p + q) = deriv p + deriv q" $
    \p q -> deriv (p + q) === (deriv p + deriv q :: Poly V.Vector Int)
  , testProperty "deriv (p * q) = p * deriv q + q * deriv p" $
    \p q -> deriv (p * q) === (p * deriv q + q * deriv p :: Poly V.Vector Int)
  -- , testProperty "deriv (subst p q) = deriv q * subst (deriv p) q" $
  --   \(p :: Poly V.Vector Int) (q :: Poly U.Vector Int) ->
  --     deriv (subst p q) === deriv q * subst (deriv p) q
  ]
