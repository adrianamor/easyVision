-----------------------------------------------------------------------------
{- |
Module      :  Contours.Polyline
Copyright   :  (c) Alberto Ruiz 2007-11
License     :  GPL

Maintainer  :  Alberto Ruiz (aruiz at um dot es)
Stability   :  provisional

Some operations with polylines.

-}
-----------------------------------------------------------------------------

module Contours.Polyline (
-- * Operations
    perimeter,
    area, orientedArea,
-- * Normalization
    centerShape,
    normalShape,
    boxShape,
    whitenContour, whitener, equalizeContour,
    isEllipse,
-- * Fourier Transform
    fourierPL, invFou, normalizeStart, shiftStart,
    norm2Cont,
-- * K orientation
    icaAngles,
    kurtCoefs, kurtAlpha, kurtosisX,
    skewX, 
-- * Reduction
    douglasPeucker, douglasPeuckerClosed,
    selectPolygons, cleanPol,
-- * Convex Hull
    convexHull,
-- * Auxiliary tools
    momentsContour, momentsBoundary,
    eig2x2Dir, asSegments, longestSegments, transPol,
    pentominos,
    bounding,
    roi2poly, poly2roi
)
where

import ImagProc.Base
import Debug.Trace
import Data.List(sortBy, maximumBy, zipWith4, sort,foldl', tails)
import Numeric.LinearAlgebra
import Util.Homogeneous
import Util.Misc(diagl)
import Util.Rotation
import Util.Misc(degree)
import Numeric.GSL.Polynomials(polySolve)
import Numeric.GSL.Fourier(ifft)

-- | (for an open polyline is the length)
perimeter :: Polyline -> Double
perimeter (Open l) = perimeter' l
perimeter (Closed l) = perimeter' (last l:l)

perimeter' [_] = 0
perimeter' (a:b:rest) = distPoints a b + perimeter' (b:rest)

area :: Polyline -> Double
area = abs . orientedArea

-- | Oriented area of a closed polyline. The clockwise sense is positive in the x-y world frame (\"floor\",z=0) and negative in the camera frame.
orientedArea :: Polyline -> Double
orientedArea (Open _) = error "undefined orientation of open polyline"
orientedArea (Closed l) = -0.5 * orientation' (last l:l)

orientation' [_] = 0
orientation' (Point x1 y1:r@(Point x2 y2:_)) = x1*y2-x2*y1 + orientation' r

----------------------------------------------------------------------

-- | Removes nodes in closed polyline such that the orthogonal distance 
--   from the remaining line is less than a given epsilon
douglasPeuckerClosed :: Double -> [Pixel] -> [Pixel]
douglasPeuckerClosed eps (a:b:ls) = b : case criticalPoint (eps^2) b a ls of
    Nothing -> [b]
    Just c  -> left ++ right where
        (l,_:r) = break (==c) ls
        left = douglasPeucker' (eps^2) b c l
        right = douglasPeucker' (eps^2) c a r

-- | Removes nodes in an open polyline such that the orthogonal distance 
--   from the remaining line is less than a given epsilon
douglasPeucker :: Double -> [Pixel] -> [Pixel]
douglasPeucker eps list = a: douglasPeucker' (eps^2) a b list
    where a = head list
          b = last list

douglasPeucker' eps2 a b ls = case criticalPoint eps2 a b ls of
    Nothing -> [b]
    Just c  -> left ++ right where
        (l,_:r) = break (==c) ls
        left = douglasPeucker' eps2 a c l
        right = douglasPeucker' eps2 c b r

perpDistAux :: Int -> Int -> Double -> Int -> Int -> Int -> Int -> Double
perpDistAux lx ly l2 x1 y1 x3 y3 = d2 where
    d2 = p2 - a'*a'/l2
    p2   = fromIntegral $ px*px + py*py
    px   = x3-x1
    py   = y3-y1
    a'   = fromIntegral $ lx*px+ly*py

perpDist (Pixel x1 y1) (Pixel x2 y2) = (f,l2) where
    lx = x2-x1
    ly = y2-y1
    l2 = fromIntegral $ lx*lx+ly*ly
    f (Pixel x3 y3) = perpDistAux lx ly l2 x1 y1 x3 y3

on f g = \x y -> f (g x) (g y)

criticalPoint eps p1 p2 [] = Nothing

criticalPoint eps2 p1 p2 p3s = r where
    (f,l2) = perpDist p1 p2
    p3 = maximumBy (compare `on` f) p3s
    r = if f p3 > eps2
        then Just p3
        else Nothing

----------------------------------------------------------------------

asSegments :: Polyline -> [Segment]
asSegments (Open ps') = zipWith Segment ps' (tail ps')
asSegments (Closed ps) = asSegments $ Open $ ps++[head ps]

----------------------------------------------------------------------

auxContour (s,sx,sy,sx2,sy2,sxy) seg@(Segment (Point x1 y1) (Point x2 y2))
    = (s+l,
       sx+l*(x1+x2)/2,
       sy+l*(y1+y2)/2,
       sx2+l*(x1*x1 + x2*x2 + x1*x2)/3,
       sy2+l*(y1*y1 + y2*y2 + y1*y2)/3,
       sxy+l*(2*x1*y1 + x2*y1 + x1*y2 + 2*x2*y2)/6)
  where l = segmentLength seg

auxSolid (s,sx,sy,sx2,sy2,sxy) seg@(Segment (Point x1 y1) (Point x2 y2))
    = (s   + (x1*y2-x2*y1)/2,
       sx  + ( 2*x1*x2*(y2-y1)-x2^2*(2*y1+y2)+x1^2*(2*y2+y1))/12,
       sy  + (-2*y1*y2*(x2-x1)+y2^2*(2*x1+x2)-y1^2*(2*x2+x1))/12,
       sx2 + ( (x1^2*x2+x1*x2^2)*(y2-y1) + (x1^3-x2^3)*(y1+y2))/12,
       sy2 + (-(y1^2*y2+y1*y2^2)*(x2-x1) - (y1^3-y2^3)*(x1+x2))/12,
       sxy + ((x1*y2-x2*y1)*(x1*(2*y1+y2)+x2*(y1+2*y2)))/24)

moments2Gen method l = (mx,my,cxx,cyy,cxy)
    where (s,sx,sy,sx2,sy2,sxy) = (foldl' method (0,0,0,0,0,0). asSegments . Closed) l
          mx = sx/s
          my = sy/s
          cxx = sx2/s - mx*mx
          cyy = sy2/s - my*my
          cxy = sxy/s - mx*my

-- | Mean and covariance matrix of a continuous piecewise-linear contour.
momentsContour :: [Point] -- ^ closed polyline
                 -> (Double,Double,Double,Double,Double) -- ^ (mx,my,cxx,cyy,cxy)
momentsContour = moments2Gen auxSolid

-- | Mean and covariance matrix of the boundary of a continuous piecewise-linear contour.
momentsBoundary :: [Point] -- ^ closed polyline
                 -> (Double,Double,Double,Double,Double) -- ^ (mx,my,cxx,cyy,cxy)
momentsBoundary = moments2Gen auxContour

-- | Structure of a 2x2 covariance matrix
eig2x2Dir :: (Double,Double,Double) -- ^ (cxx,cyy,cxy)
          -> (Double,Double,Double) -- ^ (v1,v2,angle), the eigenvalues of cov (v1>v2), and angle of dominant eigenvector
eig2x2Dir (cxx,cyy,cxy) = (l1,l2,a')
    where ra = sqrt(abs $ cxx*cxx + 4*cxy*cxy -2*cxx*cyy + cyy*cyy)
          l1 = 0.5*(cxx+cyy+ra)
          l2 = 0.5*(cxx+cyy-ra)
          a = atan2 (2*cxy) ((cxx-cyy+ra))
          a' | abs cxy < eps && cyy > cxx = pi/2
             | otherwise = a

-- | Equalizes the eigenvalues of the covariance matrix of a continuous piecewise-linear contour. It preserves the general scale, position and orientation.
equalizeContour :: Polyline -> Polyline
equalizeContour c@(Closed ps) = transPol t c where
    (mx,my,cxx,cyy,cxy) = momentsContour ps
    (l1,l2,a) = eig2x2Dir (cxx,cyy,cxy)
    t = desp (mx,my) <> rot3 (-a) <> diag (fromList [sqrt (l2/l1),1,1]) <> rot3 (a) <> desp (-mx,-my)

-- | Finds a transformation that equalizes the eigenvalues of the covariance matrix of a continuous piecewise-linear contour. It is affine invariant modulo rotation.
whitener :: Polyline -> Matrix Double
whitener (Closed ps) = t where
    (mx,my,cxx,cyy,cxy) = momentsContour ps
    (l1,l2,a) = eig2x2Dir (cxx,cyy,cxy)
    t = diag (fromList [1/sqrt l1,1/sqrt l2,1]) <> rot3 (a) <> desp (-mx,-my)

whitenContour t = transPol w t where w = whitener t

transPol t (Closed ps) = Closed $ map l2p $ ht t (map p2l ps)

p2l (Point x y) = [x,y]
l2p [x,y] = Point x y

----------------------------------------------------------

-- | Exact Fourier series of a piecewise-linear closed curve
fourierPL :: Polyline -> (Int -> Complex Double)

fourierPL c = f
    where
        g = fourierPL' c
        p = map g [0..]
        n = map g [0,-1 .. ]
        f w | w >= 0    = p !! w
            | otherwise = n !! (-w)

fourierPL' (Closed ps) = g where
    (zs,ts,aAs,hs) = prepareFourierPL ps
    g0 = 0.5 * sum (zipWith4 gamma zs ts (tail zs) (tail ts))
        where gamma z1 t1 z2 t2 = (z2+z1)*(t2-t1)
    g 0 = g0
    g w = k* ((vhs**w') <.> vas)
        where k = recip (2*pi*w'')^2
              w' = fromIntegral w  :: Vector (Complex Double)
              w'' = fromIntegral w :: Complex Double
    vhs = fromList hs
    vas = fromList $ take (length hs) aAs

prepareFourierPL c = (zs,ts,aAs,hs) where
    zs = map p2c (c++[head c])
        where p2c (Point x y) = x:+y
    ts = map (/last acclen) acclen
        where acclen = scanl (+) 0 (zipWith sl zs (tail zs))
              sl z1 z2 = abs (z2-z1)
    hs = tail $ map exp' ts
        where exp' t = exp (-2*pi*i*t)
    as = cycle $ zipWith4 alpha zs ts (tail zs) (tail ts)
        where alpha z1 t1 z2 t2 = (z2-z1)/(t2-t1)
    aAs = zipWith (-) as (tail as)


--------------------------------------------------------------------------------
-- | The average squared distance to the origin, assuming a parameterization between 0 and 1.
-- | it is the same as sum [magnitude (f k) ^2 | k <- [- n .. n]] where n is sufficiently large
-- | and f = fourierPL contour
norm2Cont :: Polyline -> Double
norm2Cont c@(Closed ps) = 1/3/perimeter c * go (ps++[head ps]) where
    go [_] = 0
    go (a@(Point x1 y1) : b@(Point x2 y2) : rest) =
        distPoints a b *
        (x1*x1 + x2*x2 + x1*x2 + y1*y1 + y2*y2 + y1*y2)
        + go (b:rest)

----------------------------------------------------------------------

cang p1@(Point x1 y1) p2@(Point x2 y2) p3@(Point x3 y3) = c
  where
    dx1 = (x2-x1)
    dy1 = (y2-y1)
    
    dx2 = (x3-x2)
    dy2 = (y3-y2)
    
    l1 = sqrt (dx1**2 + dy1**2)
    l2 = sqrt (dx2**2 + dy2**2)

    c = (dx1*dx2 + dy1*dy2) / l1 / l2

areaTriang p1 p2 p3 = sqrt $ p * (p-d1) * (p-d2) * (p-d3)
  where
    d1 = distPoints p1 p2
    d2 = distPoints p1 p3
    d3 = distPoints p2 p3
    p = (d1+d2+d3)/2

----------------------------------------------------------------------

cleanPol tol (Closed ps) = Closed r
  where
    n = length ps
    r = map snd . filter ((<tol).abs.fst) . map go . take n . tails $ ps++ps
    go (p1:p2:p3:_) = (cang p1 p2 p3, p2)

longestSegments k poly = filter ok ss
    where ss = asSegments poly
          th = last $ take k $ sort $ map (negate.segmentLength) ss
          ok s = segmentLength s >= -th

reducePolygonTo n poly = Closed $ segsToPoints $ longestSegments n poly


segsToPoints p = stp $ map segToHomogLine $ p ++ [head p]
  where
    segToHomogLine s = cross (fromList [px $ extreme1 $ s, py $ extreme1 $ s, 1])
                             (fromList [px $ extreme2 $ s, py $ extreme2 $ s, 1])

    stp [] = []
    stp [_] = []
    stp (a:b:rest) = inter a b : stp (b:rest)

    inter l1 l2 = Point x y where [x,y] = toList $ inHomog (cross l1 l2)

tryPolygon eps n poly = if length (polyPts r) == n && abs((a1-a2)/a1) < eps && ok then [r] else []
    where r = reducePolygonTo n poly
          a1 = orientedArea poly
          a2 = orientedArea r
          p = perimeter r
          l = minimum $ map segmentLength (asSegments r)
          ok = l > p / fromIntegral n / 10

selectPolygons eps n = concatMap (tryPolygon eps n)

----------------------------------------------------------------------

auxKurt k seg@(Segment (Point x1 y1) (Point x2 y2)) =
     k + (x1**4*x2*(y1 - y2) + 
          x1**3*x2**2*
           (y1 - y2) + 
          x1**2*x2**3*
           (y1 - y2) + 
          x1*x2**4*
           (y1 - y2) - 
          x1**5*(2*y1 + y2) + 
          x2**5*(y1 + 2*y2))
       / 30

kurtosisX p = foldl' auxKurt 0 (asSegments p) 

----------------------------------------------------------------------

kC 0 seg@(Segment (Point x1 y1) (Point x2 y2)) =
    ((2*x1 + x2)*y1**5 + 
    (-x1 + x2)*y1**4*y2 + 
    (-x1 + x2)*y1**3*y2**2 + 
    (-x1 + x2)*y1**2*y2**3 + 
    (-x1 + x2)*y1*y2**4 - 
    (x1 + 2*x2)*y2**5)/30

kC 1 seg@(Segment (Point x1 y1) (Point x2 y2)) =
   (-2*y1**6 + 2*y2**6 + 
    x1**2*(y1 - y2)*
     (10*y1**3 + 
       6*y1**2*y2 + 
       3*y1*y2**2 + 
       y2**3) + 
    x2**2*(y1 - y2)*
     (y1**3 + 
       3*y1**2*y2 + 
       6*y1*y2**2 + 
       10*y2**3) + 
    2*x1*x2*
     (2*y1**4 + 
       y1**3*y2 - 
       y1*y2**3 - 
       2*y2**4))/30

kC 2 seg@(Segment (Point x1 y1) (Point x2 y2)) =
    (y1**3*
     (20*x1**3 + 
       6*x1**2*x2 + 
       3*x1*x2**2 + 
       x2**3 - 
       10*x1*y1**2 + 
       x2*y1**2) - 
    (x1 - x2)*y1**2*
     (6*x1**2 + 
       6*x1*x2 + 
       3*x2**2 + y1**2)*
     y2 - 
    (x1 - x2)*y1*
     (3*x1**2 + 
       6*x1*x2 + 
       6*x2**2 + y1**2)*
     y2**2 - 
    (x1**3 + 
       3*x1**2*x2 + 
       6*x1*x2**2 + 
       20*x2**3 + 
       (x1 - x2)*y1**2)*
     y2**3 + 
    (-x1 + x2)*y1*
     y2**4 - 
    (x1 - 10*x2)*y2**5)/30

kC 3 seg@(Segment (Point x1 y1) (Point x2 y2)) = 
    (2*x1**3*x2*(y1 - y2)*
     (2*y1 + y2) + 
    x1**4*
     (20*y1**2 - 
       4*y1*y2 - y2**2)
     + x1**2*
     (3*x2**2*y1**2 - 
       20*y1**4 - 
       4*y1**3*y2 - 
       3*
        (x2**2 + y1**2)*
        y2**2 - 
       2*y1*y2**3 - 
       y2**4) + 
    x2**2*
     (y1**4 + 
       2*y1**3*y2 + 
       3*y1**2*y2**2 + 
       4*y1*y2**3 + 
       20*y2**4 + 
       x2**2*
        (y1**2 + 
          4*y1*y2 - 
          20*y2**2)) + 
    2*x1*x2*(y1 - y2)*
     (x2**2*
        (y1 + 2*y2) + 
       (y1 + y2)*
        (2*y1**2 + 
          y1*y2 + 
          2*y2**2)))/30 
   
kC 4 seg@(Segment (Point x1 y1) (Point x2 y2)) =    
   (x1**4*x2*(y1 - y2) + 
    x1**5*
     (10*y1 - y2) + 
    x1**2*x2*(y1 - y2)*
     (x2**2 + 6*y1**2 + 
       6*y1*y2 + 3*y2**2
       ) + 
    x1*x2**2*(y1 - y2)*
     (x2**2 + 3*y1**2 + 
       6*y1*y2 + 6*y2**2
       ) + 
    x1**3*
     (x2**2*y1 - 
       20*y1**3 - 
       x2**2*y2 - 
       6*y1**2*y2 - 
       3*y1*y2**2 - 
       y2**3) + 
    x2**3*
     (y1**3 + 
       x2**2*
        (y1 - 10*y2) + 
       3*y1**2*y2 + 
       6*y1*y2**2 + 
       20*y2**3))/30

kC 5 seg@(Segment (Point x1 y1) (Point x2 y2)) =
    (2*x1**6 + 
    2*x1**3*x2*
     (y1 - y2)*
     (2*y1 + y2) + 
    2*x1*x2**3*
     (y1 - y2)*
     (y1 + 2*y2) + 
    3*x1**2*x2**2*
     (y1**2 - y2**2) - 
    x1**4*
     (10*y1**2 + 
       4*y1*y2 + y2**2)
     + x2**4*
     (-2*x2**2 + 
       y1**2 + 
       4*y1*y2 + 
       10*y2**2))/30

kC 6 seg@(Segment (Point x1 y1) (Point x2 y2)) =
    (x1**4*x2*(y1 - y2) + 
    x1**3*x2**2*
     (y1 - y2) + 
    x1**2*x2**3*
     (y1 - y2) + 
    x1*x2**4*
     (y1 - y2) - 
    x1**5*(2*y1 + y2) + 
    x2**5*(y1 + 2*y2))/30

kurtCoefs p = foldl' f (repeat 0) (asSegments p)
  where
    f cs seg = zipWith (+) cs (map g [0..6])
      where
        g k = kC k seg

cs alpha = [cos alpha ^ k * sin alpha ^ (6-k) | k <- [0..6 :: Int]]

kurtAlpha coefs alpha = sum $ zipWith (*) coefs (cs alpha)

derivCoefs [c0,c1,c2,c3,c4,c5,c6] =
    [       -c1
    , 6*c0-2*c2
    , 5*c1-3*c3
    , 4*c2-4*c4
    , 3*c3-5*c5
    , 2*c4-6*c6
    ,   c5      ]

icaAngles w = sortBy (compare `on` (negate.kur)) angs
  where
    angs = map realPart . filter ((<(0.1*degree)).abs.imagPart) . map (atan.recip) . polySolve . derivCoefs $ coefs
    coefs = kurtCoefs w
    kur = kurtAlpha coefs

--------------------------------------------------------------------------------

auxSkew k seg@(Segment (Point x1 y1) (Point x2 y2)) =
     k + (2*x1**3*x2*
           (y1 - y2) + 
          2*x1**2*x2**2*
           (y1 - y2) + 
          2*x1*x2**3*
           (y1 - y2) - 
          x1**4*
           (3*y1 + 2*y2) + 
          x2**4*(2*y1 + 3*y2))
         /40

skewX p = foldl' auxSkew 0 (asSegments p) 

----------------------------------------------------------------------

flipx = transPol (diagl[-1,1,1])

pentominos :: [(Polyline,String)]
pentominos =
    [ (Closed $ reverse [Point 0 0, Point 0 1, Point 5 1, Point 5 0], "I")
    , (flipx $ Closed $ [Point 0 0, Point 0 1, Point 3 1, Point 3 2, Point 4 2, Point 4 0], "L")
    , (Closed $ reverse [Point 0 0, Point 0 1, Point 3 1, Point 3 2, Point 4 2, Point 4 0], "J")
    , (Closed $ reverse [Point 1 0, Point 1 1, Point 0 1, Point 0 2, Point 1 2, Point 1 3,
                         Point 2 3, Point 2 2, Point 3 2, Point 3 1, Point 2 1, Point 2 0], "X")
    , (Closed $ reverse [Point 0 0, Point 0 3, Point 1 3, Point 1 1, Point 3 1, Point 3 0], "V")
    , (Closed $ reverse [Point 0 0, Point 0 1, Point 1 1, Point 1 3, Point 2 3, Point 2 1, Point 3 1, Point 3 0], "T")
    , (flipx $ Closed $ [Point 0 0, Point 0 3, Point 2 3, Point 2 1, Point 1 1, Point 1 0], "P")
    , (Closed $ reverse [Point 0 0, Point 0 3, Point 2 3, Point 2 1, Point 1 1, Point 1 0], "B")
    , (flipx $ Closed $ [Point 0 2, Point 0 3, Point 2 3, Point 2 1, Point 3 1, Point 3 0, Point 1 0, Point 1 2], "Z")
    , (Closed $ reverse [Point 0 2, Point 0 3, Point 2 3, Point 2 1, Point 3 1, Point 3 0, Point 1 0, Point 1 2], "S")
    , (Closed $ reverse [Point 0 0, Point 0 2, Point 1 2, Point 1 1, Point 2 1, Point 2 2, Point 3 2, Point 3 0], "U")
    , (flipx $ Closed $ [Point 0 0, Point 0 1, Point 2 1, Point 2 2, Point 3 2, Point 3 1, Point 4 1, Point 4 0], "Y")
    , (Closed $ reverse [Point 0 0, Point 0 1, Point 2 1, Point 2 2, Point 3 2, Point 3 1, Point 4 1, Point 4 0], "Y'")
    , (flipx $ Closed $ [Point 0 1, Point 0 3, Point 1 3, Point 1 2, Point 3 2, Point 3 1,
                         Point 2 1, Point 2 0, Point 1 0, Point 1 1], "F")
    , (Closed $ reverse [Point 0 1, Point 0 3, Point 1 3, Point 1 2, Point 3 2, Point 3 1,
                         Point 2 1, Point 2 0, Point 1 0, Point 1 1], "Q")
    , (flipx $ Closed $ [Point 0 1, Point 0 2, Point 2 2, Point 2 1, Point 4 1, Point 4 0, Point 1 0, Point 1 1], "N")
    , (Closed $ reverse [Point 0 1, Point 0 2, Point 2 2, Point 2 1, Point 4 1, Point 4 0, Point 1 0, Point 1 1], "N'")
    , (Closed $ reverse [Point 0 1, Point 0 3, Point 1 3, Point 1 2, Point 2 2, Point 2 1,
                         Point 3 1, Point 3 0, Point 1 0, Point 1 1], "W")    
    ]

----------------------------------------------------------------------

shiftStart :: Double -> (Int -> Complex Double) -> (Int -> Complex Double)
shiftStart r f = \w -> cis (fromIntegral w*r) * f w

normalizeStart :: (Int -> Complex Double) -> (Int -> Complex Double)
normalizeStart f = shiftStart (-t) f
    where t = phase ((f (1)- (conjugate $ f(-1))))

invFou :: Int -> Int -> (Int -> Complex Double) -> Polyline
invFou n w fou = Closed r where
    f = fromList $ map fou [0..w] ++ replicate (n- 2*w - 1) 0 ++ map fou [-w,-w+1.. (-1)]
    r = map c2p $ toList $ ifft (fromIntegral n *f)
    c2p (x:+y) = Point x y

----------------------------------------------------------------------

convexHull :: [Point] -> [Point]
convexHull ps = go [q0] rs
  where
    q0:qs = sortBy (compare `on` (\(Point x y) -> (y,x))) ps
    rs = sortBy (compare `on` (ncosangle q0)) qs

    go [p] [x,q]                     = [p,x,q]
    go [p] (x:q:r)   | isLeft p x q  = go [x,p] (q:r)
                     | otherwise     = go [p]   (q:r)
    go (p:c) [x]     | isLeft p x q0 = x:p:c
                     | otherwise     =   p:c
    go (p:c) (x:q:r) | isLeft p x q  = go (x:p:c)   (q:r)
                     | otherwise     = go c       (p:q:r)
    
    ncosangle p1@(Point x1 y1) p2@(Point x2 y2) = (x1-x2) / distPoints p1 p2

    isLeft p1@(Point x1 y1) p2@(Point x2 y2) p3@(Point x3 y3) = 
        (x2 - x1)*(y3 - y1) - (y2 - y1)*(x3 - x1) > 0

----------------------------------------------------------------------

bounding :: Polyline -> Polyline
bounding p = Closed [Point x2 y2, Point x1 y2, Point x1 y1, Point x2 y1] 
  where
    x1 = minimum xs
    x2 = maximum xs
    y1 = minimum ys
    y2 = maximum ys
    xs = map px (polyPts p)
    ys = map py (polyPts p)

roi2poly :: Size -> ROI -> Polyline
roi2poly sz (ROI r1 r2 c1 c2) = Closed $ pixelsToPoints sz p
  where
    p = [Pixel r1 c1, Pixel r1 c2, Pixel r2 c2, Pixel r2 c1]

poly2roi :: Size -> Polyline -> ROI
poly2roi sz p = ROI r1 r2 c1 c2
  where
    (Closed [p1,_,p3,_]) = bounding p
    [Pixel r1 c1, Pixel r2 c2] = pointsToPixels sz [p1,p3]

----------------------------------------------------------------------

-- | centered
centerShape :: Polyline -> Polyline
centerShape c = transPol h c
 where
   (x,y,_,_,_) = momentsContour (polyPts c)
   h = desp (-x,-y)

-- | centered and unit max std
normalShape :: Polyline -> Polyline
normalShape c = transPol h c
 where
   (x,y,sx,sy,_) = momentsContour (polyPts c)
   h = scaling (1/ sqrt( max sx sy)) <> desp (-x,-y)

-- | centered and the middle of bounding box of height 2
boxShape :: Polyline -> Polyline
boxShape c = transPol h c
  where
    Closed [Point x2 y2, _, Point x1 y1, _] = bounding c
    h = scaling (2/(y2-y1)) <> desp (-(x1+x2)/2,-(y1+y2)/2)

----------------------------------------------------------------------

-- | checks if a polyline is very similar to an ellipse.
isEllipse :: Int -- ^ tolerance (per 1000 of total energy) (e.g. 10)
          -> Polyline -> Bool
isEllipse tol c = (ft-f1)/ft < fromIntegral tol/1000 where
    wc = whitenContour c   -- required?
    f  = fourierPL wc
    f0 = magnitude (f 0)
    f1 = sqrt (magnitude (f (-1)) ^2 + magnitude (f 1) ^2)
    ft = sqrt (norm2Cont wc - f0 ^2)
