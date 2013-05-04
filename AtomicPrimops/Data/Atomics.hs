{-# LANGUAGE  MagicHash, UnboxedTuples, BangPatterns, ScopedTypeVariables #-}

-- | Provides atomic memory operations on IORefs and Mutable Arrays.
--
--   Pointer equality need not be maintained by a Haskell compiler.  For example, Int
--   values will frequently be boxed and unboxed, changing the pointer identity of
--   the thunk.  To deal with this, the compare-and-swap (CAS) approach used in this
--   module is uses a /sealed/ representation of pointers into the Haskell heap
--   (`Tickets`).  Currently, the user cannot coin new tickets, rather a `Ticket`
--   provides evidence of a past observation, and grants permission to make a future
--   change.
module Data.Atomics 
 (
   -- * Types for atomic operations
   Ticket, peekTicket, -- CASResult(..),

   -- * Atomic operations on mutable arrays
   casArrayElem, readArrayElem, 

   -- * Atomic operations on IORefs
   readForCAS, casIORef,

   -- * Atomic operations on STRefs
--   readSTRefForCAS, casSTRef,
   
   -- * Atomic operations on raw MutVars
   readMutVarForCAS, casMutVar
      
 ) where

import Control.Monad.ST (stToIO)
import Data.Primitive.Array (MutableArray(MutableArray))
import Data.Atomics.Internal (casArray#, readForCAS#, casMutVarTicketed#, Ticket)
import Data.Int -- TEMPORARY

import Data.IORef
import GHC.IORef
import GHC.STRef
import GHC.ST
import GHC.Prim
import GHC.Arr 
import GHC.Base (Int(I#))
import GHC.IO (IO(IO))
import GHC.Word (Word(W#))

--------------------------------------------------------------------------------

{-# INLINE casArrayElem #-}
casArrayElem :: MutableArray RealWorld a -> Int -> Ticket a -> a -> IO (Bool, Ticket a)
-- casArrayElem arr i old new = stToIO (casArrayST arr i old new)
casArrayElem (MutableArray arr#) (I# i#) old new = IO$ \s1# ->
 case casArray# arr# i# old new s1# of 
   (# s2#, x#, res #) -> (# s2#, (x# ==# 0#, res) #)


{-# INLINE readArrayElem #-}
readArrayElem :: forall a . MutableArray RealWorld a -> Int -> IO (Ticket a)
-- readArrayElem = unsafeCoerce# readArray#
readArrayElem (MutableArray arr#) (I# i#) = IO $ \ st -> unsafeCoerce# (fn st)
  where
    fn :: State# RealWorld -> (# State# RealWorld, a #)
    fn = readArray# arr# i#

{-# INLINE casArrayST #-}
-- -- | Write a value to the array at the given index:
-- casArrayST :: MutableArray s a -> Int -> a -> a -> ST s (Bool, a)
casArrayST :: MutableArray RealWorld a -> Int -> Ticket a -> a -> ST RealWorld (Bool, Ticket a)
casArrayST (MutableArray arr#) (I# i#) old new = ST$ \s1# ->
 case casArray# arr# i# old new s1# of 
   (# s2#, x#, res #) -> (# s2#, (x# ==# 0#, res) #)


--------------------------------------------------------------------------------

{-# INLINE readForCAS #-}
readForCAS :: IORef a -> IO ( Ticket a )
readForCAS (IORef (STRef mv)) = readMutVarForCAS mv

{-# INLINE casIORef #-}
-- | Performs a machine-level compare and swap operation on an
-- 'IORef'. Returns a tuple containing a 'Bool' which is 'True' when a
-- swap is performed, along with the 'current' value from the 'IORef'.
-- 
-- Note \"compare\" here means pointer equality in the sense of
-- 'GHC.Prim.reallyUnsafePtrEquality#'.
casIORef :: IORef a  -- ^ The 'IORef' containing a value 'current'
         -> Ticket a -- ^ A ticket for the 'old' value
         -> a        -- ^ The 'new' value to replace 'current' if @old == current@
--         -> IO (CASResult a)         
         -> IO (Bool, Ticket a)
casIORef (IORef (STRef var)) old new = casMutVar var old new 


--------------------------------------------------------------------------------

-- | A ticket contains or can get the usable Haskell value.
peekTicket :: Ticket a -> a 
peekTicket = unsafeCoerce#



{-# INLINE readMutVarForCAS #-}
readMutVarForCAS :: MutVar# RealWorld a -> IO ( Ticket a )
readMutVarForCAS !mv = IO$ \ st -> readForCAS# mv st

{-# INLINE casMutVar #-}
-- | MutVar counterpart of `casIORef`.
-- 
casMutVar :: MutVar# RealWorld a -> Ticket a -> a -> IO (Bool, Ticket a)
-- casMutVar :: MutVar# RealWorld a -> Ticket a -> a -> IO (CASResult a)
casMutVar !mv !tick !new = IO$ \st -> 
  case casMutVarTicketed# mv tick new st of 
    (# st, flag, tick' #) ->
      (# st, (flag ==# 0#, tick') #)
--      (# st, if flag ==# 0# then Succeed tick' else Fail tick' #)
--      if flag ==# 0#    then       else (# st, Fail (W# tick')  #)


