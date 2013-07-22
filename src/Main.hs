-----------------------------------------------------------------------------
--
-- Module      :  Main
-- Copyright   :  (c) 2012-13 Brian W Bush
-- License     :  MIT
--
-- Maintainer  :  Brian W Bush <b.w.bush@acm.org>
-- Stability   :  Stable
-- Portability :  Portable
--
-- |  Command-line access to Google APIs.
--
-----------------------------------------------------------------------------


{-# LANGUAGE DeriveDataTypeable #-}


module Main (
    main
) where


import Control.Monad (liftM)
import Data.Data(Data(..))
import qualified Data.ByteString.Lazy as LBS (readFile, writeFile)
import Data.Maybe (mapMaybe)
import Network.Google (AccessToken, toAccessToken)
import Network.Google.Bookmarks (listBookmarks)
import Network.Google.Books (listBookshelves, listBooks)
import Network.Google.Contacts (extractGnuPGNotes, listContacts)
import qualified Network.Google.OAuth2 as OA2 (OAuth2Client(..), OAuth2Tokens(..), exchangeCode, formUrl, googleScopes, refreshTokens)
import Network.Google.Picasa (defaultUser, listAlbums, listPhotos)
import Network.Google.Storage (StorageAcl(Private), deleteObject, getBucket, getObject, headObject, putObject)
import Network.Google.Storage.Encrypted (getEncryptedObject, putEncryptedObject)
import Network.Google.Storage.Sync (sync)
import Network.Socket.Internal (withSocketsDo)
import System.Console.CmdArgs
import Text.JSON (encode)
import Text.XML.Light (ppTopElement)


-- | Definition of command-line parameters.
data HGData =
    OAuth2Url {
      client :: String
   }
  | OAuth2Exchange {
      client :: String
    , secret :: String
    , code :: String
    , tokens :: FilePath
  }
  | OAuth2Refresh {
      client :: String
    , secret :: String
    , refresh :: String
    , tokens :: FilePath
  }
  | Bookmarks {
      email :: String
    , password :: String
    , sms :: String
    , xml :: FilePath
  }
  | Contacts {
      access :: String
    , xml :: FilePath
    , notes :: Maybe FilePath
    , encrypt :: [String]
    }
  | Bookshelves {
      access :: String
    , xml :: FilePath
  }
  | Books {
      access :: String
    , shelves :: [String]
    , xml :: FilePath
  }
  | Albums {
      access :: String
    , user :: String
    , xml :: FilePath
  }
  | Photos {
      access :: String
    , user :: String
    , album :: [String]
    , xml :: FilePath
  }
  | GSList {
      access :: String
    , project :: String
    , bucket :: String
    , xml :: FilePath
    }
  | GSGet {
      access :: String
    , project :: String
    , bucket :: String
    , key :: String
    , output :: FilePath
    , decrypt :: Bool
    }
  | GSPut {
      access :: String
    , project :: String
    , bucket :: String
    , key :: String
    , input :: FilePath
    , acl :: String
    , encrypt :: [String]
    }
  | GSDelete {
      access :: String
    , project :: String
    , bucket :: String
    , key :: String
    }
  | GSHead {
      access :: String
    , project :: String
    , bucket :: String
    , key :: String
    , output :: FilePath
  }
  | GSSync {
      client :: String
    , secret :: String
    , refresh :: String
    , project :: String
    , bucket :: String
    , directory :: FilePath
    , acl :: String
    , encrypt :: [String]
    , exclusions :: Maybe FilePath
    , md5sums :: Bool
    , purge :: Bool
    }
      deriving (Show, Data, Typeable)


-- | Definition of program.
hgData :: HGData
hgData =
  modes
    [
      oAuth2Url
    , oAuth2Exchange
    , oAuth2Refresh
    , bookmarks
    , bookshelves
    , books
    , contacts
    , albums
    , photos
    , gslist
    , gsget
    , gsput
    , gsdelete
    , gshead
    , gssync
    ]
    &= summary "hgData v0.6.5, (c) 2012-13 Brian W. Bush <b.w.bush@acm.org>, MIT license."
    &= program "hgdata"
    &= help "Command-line utility for accessing Google services and APIs. Send bug reports and feature requests to <http://code.google.com/p/hgdata/issues/entry>."


-- | Generate an OAuth 2.0 URL.
oAuth2Url :: HGData
oAuth2Url = OAuth2Url
  {
    client = def &= typ "ID" &= help "Client ID"
  }
    &= name "oauth2-url"
    &= help "Generate an OAuth 2.0 URL."
    &= details
      [
        "Use this command to generate a URL for OAuth 2.0 authentication of this client program with Google APIs."
      , ""
      , "Visit the URL generated by the command and authorize the application to obtain an OAuth 2.0 authorization code the can be exchanged for tokens with the \"hgdata oauth2exchange\" command."
      , ""
      , "A \"Client ID for installed applications\" can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Exchange an OAuth 2.0 code for tokens.
oAuth2Exchange :: HGData
oAuth2Exchange = OAuth2Exchange
  {
    client = def &= typ "ID" &= help "OAuth 2.0 client ID"
  , secret = def &= typ "SECRET" &= help "OAuth 2.0 client secret"
  , code = def &= typ "CODE" &= argPos 0
  , tokens = def &= opt "/dev/stdout" &= typFile &= argPos 1
  }
    &= name "oauth2-exchange"
    &= help "Exchange an OAuth 2.0 code for tokens."
    &= details
      [
        "Use this command to exchange an OAuth 2.0 authentication code for an access and refresh token."
      , ""
      , "An OAuth 2.0 authentication code can be obtain by visiting the URL generated by the \"hgdata oauth2url\" command."
      , ""
      , "A \"Client ID for installed applications\" and client secret can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Refresh OAuth 2.0 tokens.
oAuth2Refresh :: HGData
oAuth2Refresh = OAuth2Refresh
  {
    client = def &= typ "ID" &= help "OAuth 2.0 client ID"
  , secret = def &= typ "SECRET" &= help "OAuth 2.0 client secret"
  , refresh = def &= typ "TOKEN" &= help "OAuth 2.0 refresh token"
  , tokens = def &= opt "/dev/stdout" &= typFile &= argPos 0
  }
    &= name "oauth2-refresh"
    &= help "Refresh OAuth 2.0 tokens."
    &= details
      [
        "Use this command to refresh an OAuth 2.0 access token."
      , ""
      , "An OAuth 2.0 refresh token can be obtained using the \"hgdata oauth2exchange\" command."
      , ""
      , "A \"Client ID for installed applications\" and client secret can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | List Google bookmarks.
bookmarks :: HGData
bookmarks = Bookmarks
  {
    email = def &= typ "ADDRESS" &= help "Google e-mail address"
  , password = def &= typ "PASSWORD" &= help "Google password"
  , sms = def &= typ "TOKEN" &= help "Google SMS token"
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 0
  }
    &= help "List Google bookmarks."
    &= details
      [
        "Use this command to list the bookmarks, in XML format, for a Google account."
      ]


-- | Download Google Contacts.
contacts :: HGData
contacts = Contacts
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 0
  , notes = def &= typFile &= help "Output for GnuPG/PGP data from \"Notes\" field"
  , encrypt = def &= typ "RECIPIENT" &= help "recipient to encrypt passwords for"
  }
    &= help "Download Google Contacts."
    &= details
      [
        "Use this command to download an XML file of Google Contacts."
      , ""
      , "If the \"--notes\" flag is specified, then any GnuPG or PGP data in the Contacts' \"Notes\" field will be decrypted to the file specified. If one or more \"--encrypt\" flags are also specified, then the decrypted notes fields will be re-encrypted to the recipients specified. The GnuPG executable \"gnupg\" must be on the command-line PATH."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command."
      , ""
      , "A \"Client ID for installed applications\" and client secret can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | List bookshelves in My Library.
bookshelves :: HGData
bookshelves = Bookshelves
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 0
  }
    &= help "List bookshelves in My Library."
    &= details
      [
        "Use this command to list the bookshelves in My Library, in JSON format, for the authenticated user."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | List bookshelves in My Library.
books :: HGData
books = Books
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 0
  , shelves = def &= typ "ID" &= args
  }
    &= help "Lists books in My Library."
    &= details
      [
        "Use this command to list the books in My Library, in JSON format, for the authenticated user."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | List Picasa albums.
albums :: HGData
albums = Albums
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , user = def &= typ "ID" &= help "Picasa user ID"
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 0
  }
    &= help "List Picasa albums."
    &= details
      [
        "Use this command to list the albums, in XML format, for a Picasa user."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | List Picasa photos.
photos :: HGData
photos = Photos
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , user = def &= opt defaultUser &= typ "ID" &= help "Picasa user ID"
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 0
  , album = def &= opt "" &= typ "ALBUM" &= args
  }
    &= help "List Picasa photos."
    &= details
      [
        "Use this command to list the photos, in XML format, of album(s) for a Picasa user."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | List objects in a Google Storage bucket.
gslist :: HGData
gslist = GSList
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , project = def &= typ "ID" &= help "Google API project number"
  , bucket = def &= typ "BUCKET" &= argPos 0
  , xml = def &= opt "/dev/stdout" &= typFile &= argPos 1
  }
    &= name "gs-list"
    &= help "List objects in a Google Storage bucket."
    &= details
      [
        "Use this command to list the contents, in XML format, of a Google Storage bucket."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Get an object from a Google Storage bucket.
gsget :: HGData
gsget = GSGet
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , project = def &= typ "ID" &= help "Google API project number"
  , bucket = def &= typ "BUCKET" &= argPos 0
  , key = def &= typ "KEY" &= argPos 1
  , output = def &= opt "/dev/stdout" &= typFile &= argPos 2
  , decrypt = def &= help "Attempt to decrypt the object"
  }
    &= name "gs-get"
    &= help "Get an object from a Google Storage bucket."
    &= details
      [
        "Use this command to download an object from Google Storage."
      , ""
      , "In order for decryption to work, the GnuPG executable \"gnupg\" must be on the command-line PATH."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Put an object into a Google Storage bucket.
gsput :: HGData
gsput = GSPut
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , project = def &= typ "ID" &= help "Google API project number"
  , bucket = def &= typ "BUCKET" &= argPos 0
  , key = def &= typ "KEY" &= argPos 1
  , input = def &= opt "/dev/stdin" &= typFile &= argPos 2
  , acl = def &= opt "private" &= typ "ACL" &= argPos 3
  , encrypt = def &= typ "RECIPIENT" &= help "Recipient to encrypt for"
  }
    &= name "gs-put"
    &= help "Put an object into a Google Storage bucket."
    &= details
      [
        "Use this command to upload an object to Google Storage."
      , ""
      , "The pre-canned ACL must be one of the following: private (the default), public-read, public-read-write, authenticated-read, bucket-owner-read, bucket-owner-full-control."
      , ""
      , "In order for encryption to work, the GnuPG executable \"gnupg\" must be on the command-line PATH."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Delete an object from a Google Storage bucket.
gsdelete :: HGData
gsdelete = GSDelete
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , project = def &= typ "ID" &= help "Google API project number"
  , bucket = def &= typ "BUCKET" &= argPos 0
  , key = def &= typ "KEY" &= argPos 1
  }
    &= name "gs-delete"
    &= help "Delete an object from a Google Storage bucket."
    &= details
      [
        "Use this command to delete an object from Google Storage."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Get object metadata from a Google Storage bucket.
gshead :: HGData
gshead = GSHead
  {
    access = def &= typ "TOKEN" &= help "OAuth 2.0 access token"
  , project = def &= typ "ID" &= help "Google API project number"
  , bucket = def &= typ "BUCKET" &= argPos 0
  , key = def &= typ "KEY" &= argPos 1
  , output = def &= opt "/dev/stdout" &= typFile &= argPos 2
  }
    &= name "gs-head"
    &= help "Get object metadata from a Google Storage bucket."
    &= details
      [
        "Use this command to list information about an object in Google Storage."
      , ""
      , "An OAuth 2.0 access token can be obtained using the \"hgdata oauth2exchange\" or \"hgdata oauth2refresh\" command. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Synchronize a directory with a Google Storage bucket.
gssync :: HGData
gssync = GSSync
  {
    client = def &= typ "ID" &= help "OAuth 2.0 client ID"
  , secret = def &= typ "SECRET" &= help "OAuth 2.0 client secret"
  , refresh = def &= typ "TOKEN" &= help "OAuth 2.0 refresh token"
  , project = def &= typ "ID" &= help "Google API project number"
  , bucket = def &= typ "BUCKET" &= argPos 0
  , directory = def &= typ "DIRECTORY" &= argPos 1
  , acl = def &= opt "private" &= typ "ACL" &= argPos 2
  , encrypt = def &= typ "RECIPIENT" &= help "Recipient to encrypt for"
  , exclusions = def &= typFile &= help "File of regex exclusions"
  , md5sums = def &= help "Write file \".md5sum\" in directory"
  , purge = def &= help "Purge non-synchronized objects from the bucket"
  }
    &= name "gs-sync"
    &= help "Synchronize a directory with a Google Storage bucket."
    &= details
      [
        "Use this command to synchronize a directory to a Google Storage bucket."
      , ""
      , "The pre-canned ACL must be one of the following: private (the default), public-read, public-read-write, authenticated-read, bucket-owner-read, bucket-owner-full-control."
      , ""
      , "In order for encryption to work, the GnuPG executable \"gnupg\" must be on the command-line PATH."
      , ""
      , "The exclusion files consists on regular expressions, one per line, of paths to be excluded from the synchronization."
      , ""
      , "The \".md5sum\" file will contain the MD5 sums and filenames of the synchronized files in a format that can be used to check MD5 sums with the \"md5sum -c\" command or with \"md5deep\"."
      , ""
      , "An OAuth 2.0 refresh token can be obtained using the \"hgdata oauth2exchange\" command. A \"Client ID for installed applications\" and client secret can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>. A project ID can be obtained from the \"API Access\" section of the Google API Console <https://code.google.com/apis/console/>."
      ]


-- | Dispatch a command-line request.
dispatch :: HGData -> IO ()

dispatch (OAuth2Url clientId) =
  putStrLn $ OA2.formUrl (OA2.OAuth2Client clientId undefined) $
    mapMaybe (`lookup` OA2.googleScopes)
    [
      "Google Cloud Storage"
    , "Contacts"
    , "Picasa Web"
    , "Google Books"
    ]

dispatch (OAuth2Exchange clientId clientSecret exchangeCode tokenFile) =
  do
    tokens <- OA2.exchangeCode (OA2.OAuth2Client clientId clientSecret) exchangeCode
    writeFile tokenFile $ show tokens

dispatch (OAuth2Refresh clientId clientSecret refreshToken tokenFile) =
  do
    tokens <- OA2.refreshTokens (OA2.OAuth2Client clientId clientSecret) (OA2.OAuth2Tokens undefined refreshToken undefined undefined)
    writeFile tokenFile $ show tokens

dispatch (Bookmarks email password sms xmlOutput) =
  do
    result <- listBookmarks email password sms
    writeFile xmlOutput $ ppTopElement result

dispatch (Contacts accessToken xmlOutput passwordOutput recipients) =
  do
    contacts <- listContacts $ toAccessToken accessToken
    writeFile xmlOutput $ ppTopElement contacts
    maybe
      (return ())
      (
        \x ->
        do
          passwords <- extractGnuPGNotes recipients contacts
          writeFile x passwords
      )
      passwordOutput

dispatch (Bookshelves accessToken xmlOutput) =
  do
    result <- listBookshelves (toAccessToken accessToken)
    writeFile xmlOutput $ encode result

dispatch (Books accessToken shelves xmlOutput) =
  do
    result <- listBooks (toAccessToken accessToken) shelves
    writeFile xmlOutput $ encode result

dispatch (Albums accessToken user xmlOutput) =
  do
    let
      user' = if user == "" then defaultUser else user
    result <- listAlbums (toAccessToken accessToken) user'
    writeFile xmlOutput $ ppTopElement result

dispatch (Photos accessToken user album xmlOutput) =
  do
    let
      user' = if user == "" then defaultUser else user
      album' = if not (null album) && head album == "" then [] else album
    result <- listPhotos (toAccessToken accessToken) user' album'
    writeFile xmlOutput $ ppTopElement result

dispatch (GSList accessToken projectId bucket xmlOutput) =
  do
    result <- getBucket projectId bucket (toAccessToken accessToken)
    writeFile xmlOutput $ ppTopElement result

dispatch (GSGet accessToken projectId bucket key output decrypt) =
  do
    let getter = if decrypt then getEncryptedObject else getObject
    result <- getter projectId bucket key (toAccessToken accessToken)
    LBS.writeFile output result

dispatch (GSPut accessToken projectId bucket key input acl recipients) =
  do
    let putter = if null recipients then putObject else putEncryptedObject recipients
    bytes <- LBS.readFile input
    putter projectId (read acl) bucket key Nothing bytes Nothing (toAccessToken accessToken)
    return ()

dispatch (GSDelete accessToken projectId bucket key) =
  do
    result <- deleteObject projectId bucket key (toAccessToken accessToken)
    return ()

dispatch (GSHead accessToken projectId bucket key output) =
  do
    result <- headObject projectId bucket key (toAccessToken accessToken)
    writeFile output $ show result

dispatch (GSSync clientId clientSecret refreshToken projectId bucket directory acl recipients exclusionFile md5sums purge) =
  do
    let
      acl' = if acl == "" then Private else read acl
    exclusions <- liftM lines $ maybe (return "") readFile exclusionFile
    sync
      projectId
      acl'
      bucket
      (OA2.OAuth2Client clientId clientSecret)
      (OA2.OAuth2Tokens undefined refreshToken undefined undefined)
      directory
      recipients
      exclusions
      md5sums
      purge


-- | Main entry point.
main :: IO ()
main =
  withSocketsDo $ do
    command <- cmdArgs hgData
    dispatch command
