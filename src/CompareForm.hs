{-# LANGUAGE OverloadedStrings #-}
module CompareForm where

import qualified Arch
import           Common hiding (getStore)
import qualified Common (getStore)
import           CompareFormTemplate
import           Control.Monad
import           Control.Monad.Trans
import           Data.Maybe                           (isJust)
import           Data.String.Conversions
import           Prelude
import           UserError                            (getErrorTmpl)
import Web.Scotty.Trans (rescue, ActionT, raise, Param, redirect)
import qualified Data.Text.Internal.Lazy as LText (Text)
import Control.Monad.Trans.Reader
import Data.List (sort, intercalate)

processParams :: Maybe [Param] -> Maybe [Param]
processParams = fmap . fmap $ f
  where f (p, _) = (("package[]"), p)

getStore :: ArchCompareActionM APSs
getStore  = do
  lift $ Common.getStore <$> ask

getURL :: [String] -> String
getURL = ((++) "/comparePackage/") . intercalate "/"

getExposeURL :: String -> ArchCompareActionM String
getExposeURL x = do
  archConfig <- lift ask
  return $ (++) (getBaseUrl archConfig) x

comparePackageHandler :: ArchCompareActionM ()
comparePackageHandler = do
  archConfig <- lift ask
  store <- getStore
  requestedPackages' <- requestedPackages
  when (requestedPackages' /= sort requestedPackages')
    $ redirect $ convertString
    $ getURL $ convertString <$> sort requestedPackages'
  rescue (do
    when ( not $ length requestedPackages' >= 2) $
      raise "You need to specify atleast two requestedPackages"
    case comparePackageGetPackages requestedPackages' store of
      Right aps -> (liftIO $ getComparePackageTmpl requestedPackages' aps archConfig) >>= respondHtml
      Left e -> raise . convertString $ e
    ) (catchError requestedPackages')

comparePackageFormHandler :: ArchCompareActionM ()
comparePackageFormHandler = do
  archConfig <- lift ask
  (liftIO $ getComparePackageFormTmpl archConfig) >>= (respondHtml)

catchError :: [PTitle] -> LText.Text -> ArchCompareActionM ()
catchError pkgs e = do
  archConfig <- lift ask
  liftIO $ getErrorTmpl archConfig (convertString e) pkgs
  >>= respondHtml

withStatisticStore :: (Monad m) => (APSs -> ActionT LText.Text m ()) -> Maybe APSs -> ActionT LText.Text m ()
withStatisticStore = maybe (Web.Scotty.Trans.raise "Couldn't open database store")

requestedPackages :: (Monad m) => ActionT LText.Text m [PTitle]
requestedPackages = multiParam "package[]" >>= return . filter (/= "")

comparePackageGetPackages :: [PTitle] -> APSs -> Either String [APS]
comparePackageGetPackages requestedPackages' statisticsStore = do
  let searchPackages = Arch.searchPackageStats statisticsStore
  let packagesResult = map (searchPackages . convertString) requestedPackages' :: [Maybe APS]
  case (sequence packagesResult) of
    Just (results) -> return results
    Nothing -> Left . convertString $ "Unable to find the following requestedPackages: "  ++ show packagesNotFound where
      packagesNotFound = join $ zipWith
        (\requestedPkg packageResult -> if isJust packageResult then [] else [requestedPkg])
        requestedPackages' packagesResult
