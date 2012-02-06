import Vision.GUI
import Contours
import ImagProc

main = run (sMonitor "result" f >>> freqMonitor)

f roi x =  [  msg "grayscale"          [ Draw g ]
           ,  msg "gaussian filter"    [ Draw smooth ]
           ,  msg "median filter"      [ Draw med ]
           ,  msg "canny edges"        [ Draw (notI edges) ]
           ,  msg "Otsu threshold"     [ Draw otsu ]
           ,  msg "raw dark contours"  [ color blue, lineWd 2, draws rawconts ]
           ,  msg "reduced contours"   [ color blue, lineWd 2, draws conts ]
           ,  msg "distance transform" [ Draw disTra ]
           ]
  where
    msg s x  =  Draw [ Draw img, Draw x , winTitle s ]
    draws  = Draw . map Draw

    img    = rgb x 
    g      = setRegion roi (grayscale x)
    smooth = gauss Mask5x5 . float $ g
    med    = median Mask5x5 g
    edges  = canny (0.1,0.3) . gradients $ smooth
    otsu   = compareC8u (otsuThreshold g) IppCmpGreater g
    ((rawconts,_),_)  = otsuContours g
    conts  = map reducePolyline rawconts
    disTra = (1/60) .* distanceTransform [1,1.4,2.2] (notI edges)
