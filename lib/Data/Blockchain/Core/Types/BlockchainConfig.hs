module Data.Blockchain.Core.Types.BlockchainConfig
    ( BlockchainConfig(..)
    , targetReward
    , targetDifficulty
    ) where

import qualified Data.Aeson          as Aeson
import           Data.Aeson          ((.=), (.:))
import qualified Data.HashMap.Strict as H
import qualified Data.Time.Clock     as Time
import qualified Data.Word           as Word

import Data.Blockchain.Core.Types.Block
import Data.Blockchain.Core.Types.Difficulty

data BlockchainConfig = BlockchainConfig
    { initialDifficulty             :: Difficulty
    , targetSecondsPerBlock         :: Word.Word
    , difficultyRecalculationHeight :: Word.Word
    , initialMiningReward           :: Word.Word
    -- Defines block heights where reward changes
    -- An empty map means the current reward is always the initial reward
    , miningRewardTransitionMap     :: H.HashMap Word.Word Word.Word
    }
  deriving (Eq, Show)

-- defaultConfig :: BlockchainConfig
-- defaultConfig = BlockchainConfig


instance Aeson.ToJSON BlockchainConfig where
    toJSON BlockchainConfig{..} = Aeson.object
        [ "initialDifficulty"             .= initialDifficulty
        , "targetSecondsPerBlock"         .= targetSecondsPerBlock
        , "difficultyRecalculationHeight" .= difficultyRecalculationHeight
        , "initialMiningReward"           .= initialMiningReward
        -- TODO: serialize to json object
        -- Need to put into form: HashMap Text Aeson.Value
        , "miningRewardTransitionMap"     .= H.toList miningRewardTransitionMap
        ]

instance Aeson.FromJSON BlockchainConfig where
    parseJSON = Aeson.withObject "BlockchainConfig" $ \v -> BlockchainConfig
        <$> v .: "initialDifficulty"
        <*> v .: "targetSecondsPerBlock"
        <*> v .: "difficultyRecalculationHeight"
        <*> v .: "initialMiningReward"
        <*> ( H.fromList <$> v .: "miningRewardTransitionMap" )

targetReward :: BlockchainConfig -> Word.Word -> Word.Word
targetReward config height =
    case currentBounds of
        []     -> initialMiningReward config
        bounds -> snd (maximum bounds)
  where
    currentBounds = filter (\(h, _) -> h <= height) rewardBounds
    rewardBounds  = H.toList $ miningRewardTransitionMap config

-- TODO: account for the blockchain having two chains of the same length
-- if two chains are the same length, lowest difficulty determines the target
-- could also implement that logic upstream
-- TODO: array of blocks hold no assurances of expected invariants
-- for example block1 could be created more recently than blockN
-- should create a `SingleChain` wrapper
targetDifficulty :: BlockchainConfig -> [Block] -> Difficulty
targetDifficulty config []                                            = initialDifficulty config
targetDifficulty config _ | difficultyRecalculationHeight config == 0 = initialDifficulty config
targetDifficulty config _ | targetSecondsPerBlock config == 0         = initialDifficulty config
targetDifficulty config blocks =
    case length blocks `mod` fromIntegral recalcHeight of
        0 ->
            let recentBlocks   = take (fromIntegral recalcHeight) (reverse blocks)
                lastBlock      = head recentBlocks
                firstBlock     = last recentBlocks
                -- TODO: get rid of `abs`, move invariant into types
                diffTime       = abs $ Time.diffUTCTime (blockTime lastBlock) (blockTime firstBlock)
                avgSolveTime   = realToFrac diffTime / fromIntegral recalcHeight
                ratio          = avgSolveTime / fromIntegral (targetSecondsPerBlock config)
                lastDifficulty = difficulty (blockHeader lastBlock)
                nextDifficulty = Difficulty $ round $ ratio * toRational (unDifficulty lastDifficulty)
            in nextDifficulty

        _ -> difficulty $ blockHeader $ last blocks
  where
    recalcHeight = difficultyRecalculationHeight config
    blockTime    = time . blockHeader