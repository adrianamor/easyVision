import EasyVision
import Control.Monad((>=>))

onlyCards sz = onlyRectangles sz (sqrt 2) rgb
               >=> virtualCamera (map channelsFromRGB . concat)

main = do
    sz <- findSize
    prepare

    rects <- getFlag "--rectangles"
    let vc = if rects then onlyCards sz
                      else return . id

    (cam,ctrl) <- getCam 0 sz ~> channels
               >>= vc
               >>= monitorizeIn "video" (mpSize 10) (drawImage.rgb)
               >>= withPause

    hsvPalette

    o <- createParameters [("kb",intParam 60  0 255),
                           ("kg",intParam 100 0 255),
                           ("kw",intParam 200 0 255)]

    e <- evWindow () "pseudocolor" sz Nothing (const (kbdcam ctrl))

    launch $ inWin e $ do
        kb <- fromIntegral `fmap` (getParam o "kb" :: IO Int)
        kg <- fromIntegral `fmap` (getParam o "kg" :: IO Int)
        kw <- fromIntegral `fmap` (getParam o "kw" :: IO Int)

        img <- cam

        drawImage $ hsvToRGB
                  $ hsvCodeTest kb kg kw
                  $ rgbToHSV
                  $ rgb $ img
