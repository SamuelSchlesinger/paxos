{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}
module Paxos where

import qualified Data.Fixed
import Data.Word
import Data.Maybe (catMaybes)
import Data.Ord (Down (Down))
import Control.Monad (forM_)
import Data.List (sortBy)
import Data.Function

type Node = Word8

type SequenceNo = Word32

type Hash = (Word64, Word64)

type Timeout = Data.Fixed.Pico

data Round = Round
  { no :: SequenceNo
  , me :: Node
  }
  deriving (Eq, Ord, Show)

nextRound :: Round -> Round
nextRound rnd = Round { no = no rnd + 1, me = me rnd }

newtype Value = Value
  { valueHash :: Hash
  }
  deriving (Eq, Ord, Show)

data LeaderMessage =
  ElectMeFor Round | RequestVoteFor Round Value | IveChosen Round Value

leaderMessageRound :: LeaderMessage -> Round
leaderMessageRound = \case
  ElectMeFor rnd -> rnd
  RequestVoteFor rnd _ -> rnd

data FollowerMessage =
  LeadMeFor Round (Maybe (Round, Value)) | VoteFor Round Value

data LeaderState = Phase1 Round [(Node, Maybe (Round, Value))] Value | Phase2 Round [Node] Value | Chosen Round Value

data FollowerState = FollowerState
  { latestRound :: Round
  , accepted :: Maybe (Round, Value)
  , proposition :: Maybe Value
  , totalNodes :: Word8
  }

class Monad m => MonadPaxos m where
  sendLeaderMessage :: Node -> LeaderMessage -> m ()
  sendFollowerMessage :: Node -> FollowerMessage -> m ()
  recvLeaderMessage :: Timeout -> m (Maybe (Node, LeaderMessage))
  recvFollowerMessage :: Timeout -> m (Maybe (Node, FollowerMessage))

paxos :: MonadPaxos m => FollowerState -> m ()
paxos fstate = recvLeaderMessage 1 >>= \case -- check for messages from leader
  Nothing -> case proposition fstate of -- no messages in a long time
    Nothing -> paxos fstate -- we aren't destined to be a leader anyways
    Just v -> do
      let newRound = nextRound (latestRound fstate)
      paxosLeader fstate { latestRound = newRound } (Phase1 newRound [] v) -- attempt to become the leader
  Just (node, lmsg) -> handleLeaderMessage fstate node lmsg

handleLeaderMessage :: MonadPaxos m => FollowerState -> Node -> LeaderMessage -> m ()
handleLeaderMessage fstate node lmsg = case lmsg of
  ElectMeFor rnd -> do
    if rnd > latestRound fstate then do
      sendFollowerMessage node (LeadMeFor rnd (accepted fstate))
      paxos fstate { latestRound = rnd }
    else paxos fstate
  RequestVoteFor rnd val -> do
    if rnd > latestRound fstate then do
      sendFollowerMessage node (VoteFor rnd val)
      paxos fstate { accepted = Just (rnd, val) }
    else paxos fstate

selectSafeValue :: Value -> [(Node, Maybe (Round, Value))] -> Value
selectSafeValue val votes = do
  let sortedByRound = sortBy (compare `on` (Down . fst)) (catMaybes (map snd votes))
  case sortedByRound of
    (_topRnd, val') : _ -> val'
    [] -> val

paxosLeader :: MonadPaxos m => FollowerState -> LeaderState -> m ()
paxosLeader fstate lstate = recvFollowerMessage 1 >>= \case -- check for messages from followers
  Nothing -> recvLeaderMessage 0.1 >>= \case -- check for messages from leaders just in case
    Just (node, lmsg) -> do
      let potentialNewRound = leaderMessageRound lmsg
      if potentialNewRound > latestRound fstate then do
        handleLeaderMessage fstate { latestRound = potentialNewRound } node lmsg
      else do
        paxosLeader fstate lstate
  Just (node, fmsg) -> case lstate of
    Phase1 rnd votes val -> case fmsg of
      LeadMeFor rnd' macc ->
        if rnd == rnd' then do
          let votes' = (node, macc) : votes
          if length votes' > fromIntegral (1 + (totalNodes fstate `div` 2)) then do
            let lstate' = Phase2 rnd [] (selectSafeValue val votes)
            paxosLeader fstate lstate'
          else do
            let lstate' = Phase1 rnd votes' val
            paxosLeader fstate lstate'
        else paxosLeader fstate lstate
      _ -> paxosLeader fstate lstate -- Only LeadMeFor messages are valid in phase 1, ignore others
    Phase2 rnd votes val -> case fmsg of
      VoteFor rnd' val' -> do
        let votes' = node : votes
        if rnd == rnd'
           && val == val'
           && length votes' >= fromIntegral (1 + (totalNodes fstate `div` 2))
          then do
          let lstate' = Chosen rnd val
          forM_ [1 .. totalNodes fstate] \node' -> do
            sendLeaderMessage node' (IveChosen rnd val)
          paxosLeader fstate lstate'
        else paxosLeader fstate lstate
      _ -> paxosLeader fstate lstate
    Chosen rnd val -> paxosLeader fstate lstate
    
  
