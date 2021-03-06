{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables        #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Dense
  ( testSuite
  , ShortPoly(..)
  ) where

import Prelude hiding (gcd, quotRem, rem)
import Data.Euclidean (Euclidean(..), GcdDomain(..))
import Data.Int
import Data.Mod
import Data.Poly
import qualified Data.Poly.Semiring as S
import Data.Proxy
import Data.Semiring (Semiring)
import qualified Data.Vector as V
import qualified Data.Vector.Generic as G
import qualified Data.Vector.Unboxed as U
import Test.Tasty
import Test.Tasty.QuickCheck hiding (scale, numTests)

import Quaternion
import TestUtils

instance (Eq a, Semiring a, Arbitrary a, G.Vector v a) => Arbitrary (Poly v a) where
  arbitrary = S.toPoly . G.fromList <$> arbitrary
  shrink = fmap (S.toPoly . G.fromList) . shrink . G.toList . unPoly

instance (Eq a, Semiring a, Arbitrary a, G.Vector v a) => Arbitrary (PolyOverField (Poly v a)) where
  arbitrary = PolyOverField . S.toPoly . G.fromList . (\xs -> take (length xs `mod` 10) xs) <$> arbitrary
  shrink = fmap (PolyOverField . S.toPoly . G.fromList) . shrink . G.toList . unPoly . unPolyOverField

newtype ShortPoly a = ShortPoly { unShortPoly :: a }
  deriving (Eq, Show, Semiring, GcdDomain, Euclidean)

instance (Eq a, Semiring a, Arbitrary a, G.Vector v a) => Arbitrary (ShortPoly (Poly v a)) where
  arbitrary = ShortPoly . S.toPoly . G.fromList . (\xs -> take (length xs `mod` 10) xs) <$> arbitrary
  shrink = fmap (ShortPoly . S.toPoly . G.fromList) . shrink . G.toList . unPoly . unShortPoly

testSuite :: TestTree
testSuite = testGroup "Dense"
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
  , mySemiringLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
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
  , myNumLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

gcdDomainTests :: [TestTree]
gcdDomainTests =
  [ myGcdDomainLaws (Proxy :: Proxy (ShortPoly (Poly V.Vector Integer)))
  , myGcdDomainLaws (Proxy :: Proxy (PolyOverField (Poly V.Vector (Mod 3))))
  , myGcdDomainLaws (Proxy :: Proxy (PolyOverField (Poly V.Vector Rational)))
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
  , myIsListLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

showTests :: [TestTree]
showTests =
  [ myShowLaws (Proxy :: Proxy (Poly U.Vector ()))
  , myShowLaws (Proxy :: Proxy (Poly U.Vector Int8))
  , myShowLaws (Proxy :: Proxy (Poly V.Vector Integer))
  , myShowLaws (Proxy :: Proxy (Poly U.Vector (Quaternion Int)))
  ]

arithmeticTests :: TestTree
arithmeticTests = testGroup "Arithmetic"
  [ testProperty "addition matches reference" $
    \(xs :: [Int]) ys -> toPoly (V.fromList (addRef xs ys)) ===
      toPoly (V.fromList xs) + toPoly (V.fromList ys)
  , testProperty "subtraction matches reference" $
    \(xs :: [Int]) ys -> toPoly (V.fromList (subRef xs ys)) ===
      toPoly (V.fromList xs) - toPoly (V.fromList ys)
  , testProperty "multiplication matches reference" $
    \(xs :: [Int]) ys -> toPoly (V.fromList (mulRef xs ys)) ===
      toPoly (V.fromList xs) * toPoly (V.fromList ys)
  ]

addRef :: Num a => [a] -> [a] -> [a]
addRef [] ys = ys
addRef xs [] = xs
addRef (x : xs) (y : ys) = (x + y) : addRef xs ys

subRef :: Num a => [a] -> [a] -> [a]
subRef [] ys = map negate ys
subRef xs [] = xs
subRef (x : xs) (y : ys) = (x - y) : subRef xs ys

mulRef :: Num a => [a] -> [a] -> [a]
mulRef xs ys
  = foldl addRef []
  $ zipWith (\x zs -> map (* x) zs) xs
  $ iterate (0 :) ys

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

monomialRef :: Num a => Word -> a -> [a]
monomialRef p c = replicate (fromIntegral p) 0 ++ [c]

evalTests :: TestTree
evalTests = testGroup "eval" $ concat
  [ evalTestGroup  (Proxy :: Proxy (Poly U.Vector Int8))
  , evalTestGroup  (Proxy :: Proxy (Poly V.Vector Integer))
  , substTestGroup (Proxy :: Proxy (Poly U.Vector Int8))
  ]

evalTestGroup
  :: forall v a.
     (Eq a, Num a, Semiring a, Arbitrary a, Show a, Eq (v a), Show (v a), G.Vector v a)
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
     (Eq a, Num a, Semiring a, Arbitrary a, Show a, Eq (v a), Show (v a), G.Vector v a)
  => Proxy (Poly v a)
  -> [TestTree]
substTestGroup _ =
  [ tenTimesLess $ tenTimesLess $ tenTimesLess $
    testProperty "subst (p + q) r = subst p r + subst q r" $
    \p q r -> e (p + q) r === e p r + e q r
  , testProperty "subst x p = p" $
    \p -> e X p === p
  , testProperty "subst (monomial 0 c) p = monomial 0 c" $
    \c p -> e (monomial 0 c) p === monomial 0 c
  , tenTimesLess $ tenTimesLess $ tenTimesLess $
    testProperty "subst' (p + q) r = subst' p r + subst' q r" $
    \p q r -> e' (p + q) r === e' p r + e' q r
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
  , tenTimesLess $ tenTimesLess $ tenTimesLess $
    testProperty "deriv (subst p q) = deriv q * subst (deriv p) q" $
    \(p :: Poly V.Vector Int) (q :: Poly U.Vector Int) ->
      deriv (subst p q) === deriv q * subst (deriv p) q
  ]
