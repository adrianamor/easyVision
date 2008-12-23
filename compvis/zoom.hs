-- zoom window: click to center, wheel to zoom

import EasyVision
import Graphics.UI.GLUT hiding (Size)
import System(getArgs)
import Control.Monad(when)

main = do
    single <- getFlag "--single"
    multi  <- getFlag "--multi"
    if single
        then main1
        else if multi
                then main3
                else main2

-- a single image
main1 = do
    sz <- findSize
    file:_ <- getArgs
    prepare
    cam <- mplayer ("mf://"++file) sz
    img <- cam
    zoomer "Image" 600 (gray $ channels img)
    mainLoop

-- live zoom from a video
main2 = do
    sz <- findSize
    prepare
    cam <- getCam 0 sz ~> channels
                       >>= zoomWindow "Zoom" 600 gray
                       >>= monitorizeIn "Video" sz (drawImage.rgb)
    launch $ cam >> return ()

-- click to analyze frame in a new window
main3 = do
    sz <- findSize
    prepare
    cam <- getCam 0 sz ~> channels
    w <- evWindow False "Video" sz Nothing (mouse kbdQuit)
    launch $ inWin w $ do
        img <- cam
        drawImage (gray img)
        st <- getW w
        when st $ zoomer "zoom" 600 (gray img) >> return ()
        putW w False
  where
    mouse _ st (MouseButton LeftButton) Down _ _ = do
        st $= True
    mouse def _ a b c d = def a b c d
