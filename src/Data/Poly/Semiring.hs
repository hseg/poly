-- |
-- Module:      Data.Poly.Semiring
-- Copyright:   (c) 2019 Andrew Lelechenko
-- Licence:     BSD3
-- Maintainer:  Andrew Lelechenko <andrew.lelechenko@gmail.com>
--
-- Dense polynomials and a 'Semiring'-based interface.
--

{-# LANGUAGE PatternSynonyms #-}

module Data.Poly.Semiring
  ( Poly
  , VPoly
  , UPoly
  , unPoly
  , leading
  , toPoly
  , monomial
  , scale
  , pattern X
  , eval
  , subst
  , deriv
  , integral
  , PolyOverField(..)
  ) where

import Data.Euclidean (Field)
import Data.Semiring (Semiring)
import qualified Data.Vector.Generic as G

import Data.Poly.Internal.Dense (Poly(..), VPoly, UPoly, leading)
import qualified Data.Poly.Internal.Dense as Dense
import Data.Poly.Internal.Dense.Field ()
import Data.Poly.Internal.Dense.GcdDomain ()
import Data.Poly.Internal.PolyOverField

-- | Make 'Poly' from a vector of coefficients
-- (first element corresponds to a constant term).
--
-- >>> :set -XOverloadedLists
-- >>> toPoly [1,2,3] :: VPoly Integer
-- 3 * X^2 + 2 * X + 1
-- >>> toPoly [0,0,0] :: UPoly Int
-- 0
toPoly :: (Eq a, Semiring a, G.Vector v a) => v a -> Poly v a
toPoly = Dense.toPoly'

-- | Create a monomial from a power and a coefficient.
monomial :: (Eq a, Semiring a, G.Vector v a) => Word -> a -> Poly v a
monomial = Dense.monomial'

-- | Multiply a polynomial by a monomial, expressed as a power and a coefficient.
--
-- >>> scale 2 3 (X^2 + 1) :: UPoly Int
-- 3 * X^4 + 0 * X^3 + 3 * X^2 + 0 * X + 0
scale :: (Eq a, Semiring a, G.Vector v a) => Word -> a -> Poly v a -> Poly v a
scale = Dense.scale'

-- | Create an identity polynomial.
pattern X :: (Eq a, Semiring a, G.Vector v a, Eq (v a)) => Poly v a
pattern X = Dense.X'

-- | Evaluate at a given point.
--
-- >>> eval (X^2 + 1 :: UPoly Int) 3
-- 10
eval :: (Semiring a, G.Vector v a) => Poly v a -> a -> a
eval = Dense.eval'

-- | Substitute another polynomial instead of 'X'.
--
-- >>> subst (X^2 + 1 :: UPoly Int) (X + 1 :: UPoly Int)
-- 1 * X^2 + 2 * X + 2
subst :: (Eq a, Semiring a, G.Vector v a, G.Vector w a) => Poly v a -> Poly w a -> Poly w a
subst = Dense.subst'

-- | Take a derivative.
--
-- >>> deriv (X^3 + 3 * X) :: UPoly Int
-- 3 * X^2 + 0 * X + 3
deriv :: (Eq a, Semiring a, G.Vector v a) => Poly v a -> Poly v a
deriv = Dense.deriv'

-- | Compute an indefinite integral of a polynomial,
-- setting constant term to zero.
--
-- >>> integral (3 * X^2 + 3) :: UPoly Double
-- 1.0 * X^3 + 0.0 * X^2 + 3.0 * X + 0.0
integral :: (Eq a, Field a, G.Vector v a) => Poly v a -> Poly v a
integral = Dense.integral'
