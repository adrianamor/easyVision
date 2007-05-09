-- demo of some functions
-- left click for a menu, right click and drag to select the region of interest
-- examples:
-- ./demo penguin.dv
-- ./demo tv://

import EasyVision
import Graphics.UI.GLUT hiding (RGB,Size,minmax,histogram,Point)
import qualified Graphics.UI.GLUT as GL
import Data.IORef
import System.Exit
import System.Environment(getArgs)
import qualified Data.Map as Map
import Foreign.C.Types
import Foreign

import ImagProc.Ipp.Core
import Debug.Trace

debug x = trace (show x) x

------------------------------------------------------------

main = do
    args <- getArgs

    let opts = Map.fromList $ zip args (tail args)

    let sz = if Map.member "--size" opts
                 then mpSize $ read $ Map.findWithDefault "20" "--size" opts
                 else Size (read $ Map.findWithDefault "480" "--rows" opts)
                           (read $ Map.findWithDefault "640" "--cols" opts)

    (cam, ctrl)  <- mplayer (args!!0) sz >>= withPause

    state <- prepare "RGB"

    o <- createParameters state [("umbral",realParam 0.5 0 1),
                                 ("umbral2",intParam 128 1 255),
                                 ("size",intParam 20 0 100),
                                 ("area",percent 5),
                                 ("h",percent 20),
                                 ("smooth",intParam 3 0 10),
                                 ("smooth2",intParam 0 0 10)]

    addWindow "demo" sz Nothing (const (kbdcam ctrl)) state
                                   ---- or undefined ---

    getRoi <- roiControl (ROI 0 (height sz) (width sz`div`2) (width sz)) (kbdcam ctrl)

    let mode m = MenuEntry m $ modifyIORef state $ \s -> s {ust = m}

    attachMenu LeftButton $ Menu $ map mode
        ["RGB","Gray","Red","Green","Blue","U","V"
        , "Median","Gaussian","Laplacian","HighPass","Histogram"
        ,"Integral","Threshold","FloodFill","Contours","Contours B","Distance", "Hessian"
        ,"Corners", "Features", "Segments", "Canny", "DCT", "FFT", "Test 1", "Test 2"]

    fft <- genFFT 8 8 DivFwdByN AlgHintFast

    launch state (worker cam o getRoi fft)

-----------------------------------------------------------------

k = 1/(640*480*128)

worker cam param getRoi fft inWindow op = do

    th <- getParam param "umbral"
    th2' <- getParam param "umbral2" ::IO Int
    let th2 = fromIntegral th2'
    ph <- getParam param "h" :: IO Int
    let h1 = fromIntegral ph / 100
    smooth <- getParam param "smooth"
    smooth2 <- getParam param "smooth2" :: IO Int
    area <- getParam param "area" :: IO Int

    inWindow "demo" $ case op of

        "RGB"  ->
             cam >>= yuvToRGB >>= drawImage
        "Gray" ->
             cam >>= yuvToGray >>= drawImage
        "Red" -> do
             (r,_,_) <- cam >>= yuvToRGB_P
             drawImage r
        "Green" -> do
             (_,g,_) <- cam >>= yuvToRGB_P
             drawImage g
        "Blue" -> do
             (_,_,b) <- cam >>= yuvToRGB_P
             drawImage b
        "U" -> do
             (_,u,_) <- cam >>= yuvToYUV_P
             drawImage u
        "V" -> do
             (_,_,v) <- cam >>= yuvToYUV_P
             drawImage v
        "Integral" ->
             cam >>= yuvToGray >>= integral >>= scale32f k >>= drawImage
        "Threshold" ->
             cam >>=
             yuvToGray >>=
             scale8u32f 0 1 >>=
             thresholdVal32f th 0 IppCmpLess >>=
             thresholdVal32f th 1 IppCmpGreater >>=
             drawImage
        "FloodFill" -> do
             im' <- cam >>= yuvToGray >>= smooth2 `times` median Mask3x3 >>= binarize8u th2 True >>= copy8u
             let im = purifyWith (set8u 0) $ return $ modifyROI (shrink (5,5)) im'
                 (Size h w) = size im
                 start = (Pixel (h `div`2 ) (w `div`2))
             --(r,a,v) <- floodFill8uGrad im start 5 5 128
             (r,a,v) <- floodFill8u im start 128
             --(r,a) <- floodFill8uGrad im (snd $ maxIndx8u im) th2 th2 128
             drawImage (modifyROI (const r) im)
             pointCoordinates (size im)
             setColor 1 0 0
             text2D 0.9 0 (show (a,v))
        "Contours" -> do
             orig <- cam
             im <-yuvToGray orig >>= smooth2 `times` median Mask3x3 
             drawImage orig
             pixelCoordinates (size im)
             setColor 1 0 0
             lineWidth $= 2
             let (Size h w) = size im
                 pixarea = h*w*area`div`1000
             mapM_ (\c -> renderPrimitive LineLoop $ mapM_ vertex c) (map fst3 $ contours 100 pixarea th2 True im)
             mapM_ (\c -> renderPrimitive LineLoop $ mapM_ vertex c) (map fst3 $ contours 100 pixarea th2 False im)
        "Contours B" -> do
             orig <- cam >>= yuvToGray
             im <-(smooth2 `times` median Mask3x3) orig
             drawImage orig
             pixelCoordinates (size im)
             setColor 1 0 0
             lineWidth $= 2
             let (Size h w) = size im
                 pixarea = h*w*area`div`1000
             mapM_ (\c -> renderPrimitive LineLoop $ mapM_ vertex c) (map fst3 $ contours 100 pixarea th2 False im)
        "Distance" ->
             cam >>=
             yuvToGray >>=
             scale8u32f 0 1 >>=
             thresholdVal32f th 0 IppCmpLess >>=
             thresholdVal32f th 1 IppCmpGreater >>=
             scale32f8u 0 1 >>=
             distanceTransform [1,1.4,2.2] >>=
             scale32f (1/60) >>=
             drawImage
        "Test 1" -> do
             d <- cam >>= yuvToGray
                  >>= smooth2 `times` median Mask5x5 >>= highPass8u Mask5x5
                  >>= binarize8u th2 True >>= smooth `times` median Mask5x5
             drawImage d

        "Test 2" -> do
             d <- cam >>= yuvToGray
                  >>= median Mask5x5 >>= highPass8u Mask5x5
                  >>= binarize8u th2 False >>= smooth `times` median Mask5x5
                  >>= distanceTransform [1,1.4,2.2]
                  >>= gauss Mask5x5

             autoscale d >>= drawImage

             (mn,mx) <- minmax d
             hp <- localMax 21 (modifyROI (shrink (60,60)) d)
                   >>= thresholdVal32f (mx*h1) 0.0 IppCmpLess
                   >>= getPoints32f 500
             pixelCoordinates (size d)
             setColor 1 0 0
             pointSize $= 3
             renderPrimitive Points (mapM_ vertex hp)
             text2D 10 20 (show $ length hp)

        "Hessian" ->
             cam >>= yuvToGray >>= scale8u32f 0 1 >>=
             smooth `times` gauss Mask5x5 >>= secondOrder >>= hessian >>=
             abs32f >>= sqrt32f >>= drawImage
        "Corners" -> do
             im <- cam >>= yuvToGray >>= scale8u32f 0 1
             ips <- getCorners smooth 7 h1 500 im
             drawImage im
             pixelCoordinates (size im)
             setColor 1 0 0
             pointSize $= 3
             renderPrimitive Points (mapM_ vertex ips)
             text2D 10 20 (show $ length ips)
        "Features" -> do
             orig <- cam
             im <- yuvToGray orig >>= scale8u32f 0 1
             ips <- getSaddlePoints smooth 7 h1 500 20 10 im
             yuvToRGB orig >>= drawImage
             pointCoordinates (size im)
             setColor 1 0 0
             pointSize $= 3
             text2D 0.9 0 (show $ length ips)
             drawInterestPoints (size orig) ips
        "Canny" -> do
             roi <- getRoi
             orig <- cam
             im <- yuvToGray orig >>= scale8u32f 0 1
             F s <- (smooth `times` gauss Mask5x5) im
             gx <- sobelVert $ F s {vroi = roi `intersection` vroi s}
             gy <- sobelHoriz $ F s {vroi = roi `intersection` vroi s}
             c <- canny (gx,gy) (th/3,th) >>= scale8u32f 0 1
             copyROI32f c (theROI c) im
             drawImage im
        "Median" -> do
             orig <- cam
             im <- yuvToGray orig
             s <- (smooth `times` median Mask5x5) im
             drawImage s
        "Gaussian" -> 
             cam >>= yuvToGray >>= scale8u32f 0 1 >>= (smooth `times` gauss Mask5x5) >>= drawImage
        "Laplacian" -> 
             cam >>= yuvToGray >>= scale8u32f (-1) 1 >>= (smooth `times` gauss Mask5x5)
             >>= laplace Mask5x5
             >>= scale32f8u (-1) 1
             >>= drawImage
        "HighPass" -> do
             orig <- cam
             im <- yuvToGray orig
             s <- (smooth `times` median Mask5x5) im >>= highPass8u Mask5x5
             drawImage s
        "Histogram" -> do
             im <- cam >>= yuvToGray
             drawImage im
             pointCoordinates (size im)
             histogram [0,64 .. 256] im >>= return . show >>= text2D 0.9 0.7
        "DCT" -> do
             orig <- cam
             roi <- getRoi
             im <- yuvToGray orig >>= scale8u32f 0 1
             d <- dct (modifyROI (intersection roi) im) >>= abs32f >>= sqrt32f
             copyROI32f d (theROI d) im
             drawImage im
        "FFT" -> do
             orig <- cam
             roi <- getRoi
             let p2roi = roi `intersection`ROI (r1 roi) (r1 roi + 2^8-1) (c1 roi) (c1 roi + 2^8-1)
             im <- yuvToGray orig  >>= scale8u32f 0 1 >>= (smooth `times` gauss Mask5x5)
             d <- fft (modifyROI (const p2roi) im) >>= magnitudePack >>= powerSpectrum
             let c@(Pixel r0 c0) = cent (theROI d)
             set32f 0 (roiFrom2Pixels c c) d
             (m,Pixel rm cm) <- maxIndx d
             let ROI r1 _ c1 _ = p2roi
             print $ (rm+r1-r0,cm+c1-c0)
             print $ norm (rm+r1-r0,cm+c1-c0)
             sc <- scale32f (1/m) d
             copyROI32f sc (theROI sc) im
             drawImage im
        "Segments" -> do
             orig' <- cam >>= yuvToGray
             roi <- getRoi
             let orig = modifyROI (const roi) orig'
                 segs = segments 4 1.5 5 40 20 False orig
             drawImage orig
             setColor 1 0 0
             pointCoordinates (size orig)
             renderPrimitive Lines $ mapM_ drawSeg segs

    return op

text2D x y s = do
    rasterPos (Vertex2 x (y::GLfloat))
    renderString Helvetica12 s

cent (ROI r1 r2 c1 c2) = Pixel (r1 + (r2-r1+1)`div`2) (c1 + (c2-c1+1)`div`2)
roiFrom2Pixels (Pixel r1 c1) (Pixel r2 c2) = ROI (min r1 r2) (max r1 r2) (min c1 c2) (max c1 c2)

norm (a,b) = sqrt $ fromIntegral a^2 + fromIntegral b^2

drawSeg s = do
    vertex $ (extreme1 s)
    vertex $ (extreme2 s)


autoscale im = do
    (mn,mx) <- minmax im
    r <- scale32f8u mn mx im
    return r

fst3 (a,_,_) = a