import Control.Lens ((<&>))

import Diagrams.Prelude
import Diagrams.Backend.PGF
import Diagrams.Backend.PGF.CmdLine
import Diagrams.TwoD.Types

type D2 = Diagram PGF V2 Float

maxSum = 6 :: Int

-- The 'OnlineTeX' monad will use the given surface to run TeX commands
mkSum :: Int -> OnlineTeX D2
mkSum n = onlineHbox (displayStyle tex)
           <&> centerXY
           <&> named n 
 where
   tex | n == maxSum = sumTo maxSum
       | otherwise   = sumTo n ++ " + \\sum_{i=" ++ show (n+1) ++ "}^{" ++ show maxSum ++ "} i"

onlineDiagram = do
  sums <- mapM mkSum [0..maxSum]
  let maxHeight = maximum $ map height sums
      sumsCat   = cat' (V2 1 (-2))
                       (with & sep .~ (maxHeight * 2)
                             & catMethod .~ Distrib
                       ) sums
      arrowed   = foldr (\i -> connectOutside' arrowOpts i (i+1))
                        sumsCat
                        [0..maxSum - 1]

  return $ frame 20 arrowed

-- 'onlineMain' takes a diagram wrapped in 'OnlineTeX'
main = onlineMain onlineDiagram

arrowOpts
  = with & shaftStyle %~ lw thin
         & gaps       .~ Local 3
         & headLength .~ Local 5

displayStyle tex = "$\\displaystyle " ++ tex ++ "$"

sumTo n = show $ (n * (n + 1)) `div` 2

