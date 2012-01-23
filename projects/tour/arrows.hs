{-# LANGUAGE Arrows #-}

import Vision.GUI
import ImagProc

main = run  $    observe "source" rgb
            >>>  arr grayscale
            >>>  f
            >>>  observe "result"  (5.*)

f = proc g -> do
    let f = float g
    x <- observe "x" id -< f
    s <- (observe "s" id <<< arr (gaussS 5)) -< f
    z <- observe "inverted" notI -< g
    returnA -< x |-| s
