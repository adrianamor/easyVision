{-# OPTIONS  #-}
-----------------------------------------------------------------------------
{- |
Module      :  GSL.LinearAlgebra.Matrix
Copyright   :  (c) Alberto Ruiz 2006
License     :  GPL-style

Maintainer  :  Alberto Ruiz (aruiz at um dot es)
Stability   :  provisional
Portability :  uses ffi

Matrix and Vector representation in terms of UArrays.

(In construction...)

-}
-----------------------------------------------------------------------------
module GSL.LinearAlgebra.Matrix (

    module Complex,
    module Data.Array.Unboxed,
    UMatrix, UVector, UCMatrix, UCVector, Cx(..),
    dim, dims, rows, cols, dim', dims', rows', cols',
    trans, trans',
    diag, diag',
    disp, disp',
    toRows, toCols, fromRows, fromCols,
    toRows', toCols', fromRows', fromCols',

) where

import Data.Array.Unboxed
import GSL.LinearAlgebra.Storable(Cx(..))

import Complex
import Data.List(transpose,intersperse)
import Numeric(showGFloat)
import Data.Array.IArray

type UMatrix = UArray (Int,Int) Double
type UVector  = UArray Int Double
type UCMatrix = UArray (Int,Int,Cx) Double
type UCVector = UArray (Int,Cx) Double

dim  v | (s1,s2) <- bounds v = s2-s1+1
dims m | ((r1,c1),(r2,c2)) <- bounds m = (r2-r1+1,c2-c1+1)
rows m = (fst . dims) m
cols m = (snd . dims) m

dim'  v | ((s1,_),(s2,_)) <- bounds v = s2-s1+1
dims' m | ((r1,c1,_),(r2,c2,_)) <- bounds m = (r2-r1+1,c2-c1+1)
rows' m = (fst . dims') m
cols' m = (snd . dims') m

cosa [] = []
cosa (a:b:c) = (a:+b) : cosa c
cosa _ = error "cosa"

trans :: UMatrix -> UMatrix
trans m = ixmap ((c1,r1),(c2,r2)) (\(i,j)->(j,i)) m
    where ((r1,c1),(r2,c2)) = bounds m

trans' :: UCMatrix -> UCMatrix
trans' m = ixmap ((c1,r1,Re),(c2,r2,Im)) (\(i,j,k)->(j,i,k)) m
    where ((r1,c1,_),(r2,c2,_)) = bounds m

diag :: UVector -> UMatrix
diag v = accumArray (+) 0 ((s1,s1),(s2,s2)) [((k,k),v!k) |k <-[s1..s2]]
    where (s1,s2) = bounds v

diag' :: UCVector -> UCMatrix
diag' v = accumArray (+) 0 ((s1,s1,Re),(s2,s2,Im)) [((k,k,p),v!(k,p)) | k <-[s1..s2], p <- [Re,Im]]
    where ((s1,_),(s2,_)) = bounds v

disp :: Int -> UMatrix -> IO ()
disp n = putStrLn . showUMatrix " " (shf n)

disp' :: Int -> UCMatrix -> IO ()
disp' n = putStrLn . showUCMatrix " | " (shfc n)


toRows m = map row [r1..r2]
    where ((r1,c1),(r2,c2)) = bounds m
          row k = ixmap (c1,c2) (\j->(k,j)) m

toCols m = map col [c1..c2]
    where ((r1,c1),(r2,c2)) = bounds m
          col k = ixmap (r1,r2) (\i->(i,k)) m

toRows' m = map row [r1..r2]
    where ((r1,c1,_),(r2,c2,_)) = bounds m
          row k = ixmap ((c1,Re),(c2,Im)) (\(j,p)->(k,j,p)) m

toCols' m = map col [c1..c2]
    where ((r1,c1,_),(r2,c2,_)) = bounds m
          col k = ixmap ((r1,Re),(r2,Im)) (\(i,p)->(i,k,p)) m

fromRows :: [UVector] -> UMatrix
fromRows lv = listArray ((0,0),(r-1,c-1)) (concatMap elems lv)
    where r = length lv
          Just c = common dim lv

fromCols :: [UVector] -> UMatrix
fromCols = trans . fromRows

fromRows' :: [UCVector] -> UCMatrix
fromRows' lv = listArray ((0,0,Re),(r-1,c-1,Im)) (concatMap elems lv)
    where r = length lv
          Just c = common dim' lv

fromCols' :: [UCVector] -> UCMatrix
fromCols' = trans' . fromRows'


----------------------------------------------------------------------
-- shows a Double with n digits after the decimal point    
shf :: (RealFloat a) => Int -> a -> String     
shf dec n | abs n < 1e-10 = "0."
          | abs (n - (fromIntegral.round $ n)) < 1e-10 = show (round n) ++"."
          | otherwise = showGFloat (Just dec) n ""    
-- shows a Complex Double as a pair, with n digits after the decimal point    
shfc n z@ (a:+b) 
    | magnitude z <1e-10 = "0."
    | abs b < 1e-10 = shf n a
    | abs a < 1e-10 = shf n b ++"i"
    | b > 0         = shf n a ++"+"++shf n b ++"i"
    | otherwise     = shf n a ++shf n b ++"i"         

dsp :: String -> [[String]] -> String
dsp sep as = unlines . map unwords' $ transpose mtp where 
    mt = transpose as
    longs = map (maximum . map length) mt
    mtp = zipWith (\a b -> map (pad a) b) longs mt
    pad n str = replicate (n - length str) ' ' ++ str    
    unwords' = concat . intersperse sep

showUMatrix sep f m = dsp sep . partit (cols m) . map f . elems $ m
showUCMatrix sep f m = dsp sep . partit (cols' m) . map f . cosa . elems $ m

partit :: Int -> [a] -> [[a]]
partit _ [] = []
partit n l  = take n l : partit n (drop n l)

-- | obtains the common value of a property of a list
common :: (Eq a) => (b->a) -> [b] -> Maybe a
common f = commonval . map f where
    commonval :: (Eq a) => [a] -> Maybe a
    commonval [] = Nothing
    commonval [a] = Just a
    commonval (a:b:xs) = if a==b then commonval (b:xs) else Nothing
