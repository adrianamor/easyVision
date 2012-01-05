import EasyVision
 
main = run $ camera >>= f >>= timeMonitor
 
f :: VC Channels ImageRGB
f cam = return $ do
    x <- cam
    let r = rgb x
    print (size r)
    return r
