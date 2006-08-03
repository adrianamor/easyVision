module Trackball where

import GSL

data Quaternion = Quat {qs::Double, qv::Vector}

normalize Quat{ qs = s, qv = v } = Quat { qs = s/m, qv = recip m <> v }
    where m = sqrt $ s^2 + norm v ^ 2

infixl 5 .+.
Quat{ qs = a, qv = u } .+. Quat{ qs = t, qv = v } =
  Quat { qs = a + t , qv = u + v }

-- Grassmann product
infixl 7 .*.
Quat{ qs = a, qv = u } .*. Quat{ qs = t, qv = v } = normalize $
    Quat { qs = a*t - u<>v, qv = a<>v + t<>u + u >< v }

--------------------------------------

axisToQuat phi axis = Quat { qs = cos (phi/2), qv = sin (phi/2) <> v }
    where v = recip (norm axis) <> axis

--------------------------------------
getRotation Quat {qs = w, qv = v} = reshape 4 $ realVector
    [ 1.0 - 2.0 * (y^2 + z^2)
    , 2.0 * (x*y - w*z)
    , 2.0 * (z*x + w*y)
    , 0.0

    , 2.0 * (x*y + w*z)
    , 1.0 - 2.0 * (x^2 - z^2)
    , 2.0 * (y*z - w*x)
    , 0.0

    , 2.0 * (x*z - w*y)
    , 2.0 * (y*z + w*x)
    , 1.0 - 2.0 * (x^2 + y^2)
    , 0.0

    , 0.0
    , 0.0
    , 0.0
    , 1.0
    ] where [x,y,z] = toList v


infixl 7 ><
a >< b = asMat a <> b

asMat v = realMatrix [[ 0,-c, b],
                      [ c, 0,-a],
                      [-b, a, 0]]
    where a = v!:0
          b = v!:1
          c = v!:2

-------------------------------------------------------

-- adapted from tracball.h and trackball.c 
-- A virtual trackball implementation
-- Written by Gavin Bell for Silicon Graphics, November 1988.

projectToSphere r (x,y) = z where
    d = sqrt $ x^2 + y^2
    t = r / sqrt 2
    z = if d < r * 0.707
        then sqrt (r^2 - d^2)   -- inside sphere
        else t*t / d            -- on hyperbola

-------------------------------------------------------

{-
/*
 * Ok, simulate a track-ball.  Project the points onto the virtual
 * trackball, then figure out the axis of rotation, which is the cross
 * product of P1 P2 and O P1 (O is the center of the ball, 0,0,0)
 * Note:  This is a deformed trackball-- is a trackball in the center,
 * but is deformed into a hyperbolic sheet of rotation away from the
 * center.  This particular function was chosen after trying out
 * several variations.
 *
 * It is assumed that the arguments to this routine are in the range
 * (-1.0 ... 1.0)
 */
-}

trackball (x',y') (x,y)
    | x'==x && y'==y = Quat { qs = 1.0, qv = realVector [0,0,0]}  -- zero rotation
    | otherwise = axisToQuat phi axis
  where
    trackballSize = 0.8

    axis = p1 >< p2
    p1 = realVector [x',y',projectToSphere trackballSize (x',y')]
    p2 = realVector [x, y, projectToSphere trackballSize (x ,y )]

    phi = 2 * asin t
    t' = norm (p1-p2) / (2*trackballSize)
    t = max (-1) (min 1 t')