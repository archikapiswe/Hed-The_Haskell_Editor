> {-# Language TemplateHaskell #-}
> {-# Language LambdaCase #-}

> module TextObj where

> import HedTypes
> import qualified Yi.Rope as R
> import Lens.Micro   ((^.), (&), (.~), (%~))
> import Data.Monoid
> import Data.Char    (isPrint)
> import qualified Data.Text as T

> emptyTO::TextObj
> emptyTO = TO mempty mempty mempty mempty NoName

> getText::TextObj -> T.Text
> getText = R.toText.getYiString

> getYiString::TextObj -> R.YiString
> getYiString = mconcat .([above,leftOfC,rightOfC,below] <*>). pure

> cursorPosition::TextObj -> (Int,Int) ---- (row,col)
> cursorPosition t = (R.countNewLines $ t ^. aboveL, R.length $ t ^. leftOfCL )

> isTopLine::TextObj -> Bool
> isTopLine = R.null.above

> isBotLine::TextObj -> Bool
> isBotLine = R.null.below

> -- |cursor movement functions

> moveLeft :: TextObj -> TextObj
> moveLeft tObj | left == mempty = tObj
>               | otherwise = let (left',r') = R.splitAt (col-1) left
>                                 right' = r' <> (tObj ^. rightOfCL)
>                             in  tObj & (leftOfCL .~ left').(rightOfCL .~ right')
>  where col = R.length left
>        left = (tObj ^.leftOfCL)

> moveRight :: TextObj -> TextObj
> moveRight tObj | right == mempty || R.head right == Just ('\n') = tObj
>                | otherwise = let (l',right') = R.splitAt 1 right
>                                  left' = (tObj ^. leftOfCL) <> l'
>                              in  tObj & (leftOfCL .~ left').(rightOfCL .~ right')
>  where right = (tObj ^.rightOfCL)

> moveUp :: TextObj -> TextObj
> moveUp tObj | row ==0   = tObj
>             | otherwise = let (above',x) = R.splitAtLine (row-1) (tObj ^.aboveL)
>                               (left',right') = R.splitAt (if col < R.length x then col else (R.length x -1)) x
>                               below' = (tObj ^.leftOfCL) <> (tObj ^. rightOfCL) <> (tObj ^. belowL)
>                           in  tObj & (belowL .~ below').(aboveL .~ above').(leftOfCL .~ left').(rightOfCL .~ right')
>  where (row,col) = cursorPosition tObj

> moveDown :: TextObj -> TextObj
> moveDown tObj | isBotLine tObj = tObj
>               | otherwise = let (x,below') = R.splitAtLine 1 (tObj ^.belowL)
>                                 (left',right') = R.splitAt (if col < R.length x then col else (R.length x -1)) x
>                                 above' = (tObj ^.aboveL)<> (tObj ^.leftOfCL) <> (tObj ^. rightOfCL)
>                             in  tObj & (belowL .~ below').(aboveL .~ above').(leftOfCL .~ left').(rightOfCL .~ right')
>  where col = R.length $ (tObj ^. leftOfCL)

> moveCursor::(Int,Int) -> TextObj ->TextObj
> moveCursor (nRow,nCol) tObj =
>  let yiStr = getYiString tObj
>      (above',rest) = R.splitAtLine nRow yiStr
>      (curr,below') = R.splitAtLine 1 rest
>      c =if R.length curr > nCol then nCol else (R.length curr -1)
>      (left',right') = R.splitAt c curr
>  in tObj & (leftOfCL .~ left').(rightOfCL .~ right').(belowL .~ below').(aboveL .~ above')

-----------------------------------------------------------------------------------------

> currentLine::TextObj-> R.YiString
> currentLine t = (t ^.leftOfCL) <> (t ^.rightOfCL)

> breakLine::TextObj ->TextObj
> breakLine tObj = tObj & (aboveL %~ (<> ((tObj ^.leftOfCL) `R.snoc` '\n' )))
>                       & (leftOfCL .~ mempty)

> insertChar::Char->TextObj ->TextObj
> insertChar = \case
>  '\n' -> breakLine
>  x |isPrint x -> leftOfCL %~ (<> R.singleton x)
>  _->id

> insertMany::R.YiString ->TextObj ->TextObj
> insertMany cp = leftOfCL %~ (<> R.filter (isPrint) cp)

> -- |Delete the character preceding the cursor position, and move the
> -- cursor backwards by one character.

> deletePrevChar ::TextObj -> TextObj
> deletePrevChar t =
>  case (lt==mempty) of
>    False -> deleteChar . moveLeft $ t
>    _ | isTopLine t -> t
>    _ -> let (above',l')  = R.splitAtLine (row-1) (t ^. aboveL)
>             l'' = maybe mempty id (R.init l')
>         in  t & (leftOfCL .~ l'').(aboveL .~ above')
>  where
>   lt = t ^. leftOfCL
>   row = R.countNewLines (t ^. aboveL)

> -- |Delete the character at the cursor position.  Leaves the cursor
> -- position unchanged.  If the cursor is at the end of a line of textObject,
> -- this combines the line with the line below.

> deleteChar ::TextObj -> TextObj
> deleteChar t =
>    case (rt ==mempty) of
>       True  | R.null (t ^. belowL) -> t
>       False |rt==newLine && R.null (t ^. belowL) -> t & (rightOfCL .~ mempty)
>       False |rt==newLine  -> let (r',below')  = R.splitAtLine 1 (t ^. belowL)
>                   in t & (rightOfCL .~ r').(belowL .~ below')
>       _-> t & rightOfCL %~ (R.drop 1)
>  where
>   rt = t ^. rightOfCL
> newLine = R.singleton '\n'

> gotoEOL::TextObj -> TextObj
> gotoEOL t= t & moveRight.moveLeft.(rightOfCL .~ mempty).(leftOfCL %~ (<> t ^. rightOfCL))

> gotoBOL::TextObj -> TextObj
> gotoBOL t= t & (leftOfCL .~ mempty).(rightOfCL %~ ( t ^. leftOfCL <>))

> killToBOL::TextObj -> TextObj
> killToBOL = (leftOfCL .~ mempty)

> killToEOL::TextObj -> TextObj
> killToEOL = (rightOfCL .~ newLine)

> getNextnChars::Int->TextObj-> R.YiString
> getNextnChars n tObj = R.take n (tObj ^. rightOfCL <> tObj ^. belowL)

> getPrevnChars::Int->TextObj-> R.YiString
> getPrevnChars n tObj = R.take n (tObj ^. aboveL <> tObj ^. leftOfCL)


> delNextnChars::Int->TextObj -> (R.YiString,TextObj)
> delNextnChars n tObj = let (discarded,rest) = R.splitAt n (tObj ^. rightOfCL <> tObj ^. belowL)
>                            (right',below')  = R.splitAtLine 1 rest
>                        in  (discarded,tObj & (rightOfCL .~ right').(belowL .~ below'))

> delPrevnChars::Int->TextObj -> (R.YiString,TextObj)
> delPrevnChars n tObj = let (discarded,rest) = R.splitAt n (tObj ^. aboveL <> tObj ^. leftOfCL)
>                            n = R.countNewLines rest
>                            (above',left')  = R.splitAtLine (n-1) rest
>                        in  (discarded,tObj & (leftOfCL .~ left').(aboveL .~ above'))
