{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE TupleSections #-}

module Fsop where

import Control.Arrow
import Data.Array
import Data.Bits
import Data.Word
import Data.Void

type U8  = Word8
type U16 = Word16
type U32 = Word32
type U64 = Word64

-- FIXME: this is implemented as a C cast in bilby
downcast = fromIntegral

data R a e = Error e | Success a
type R_ e = R () e

type ErrCode = U32

data SysState
data FsState = FsState { fsop_st   :: FsopState
                       , mount_st  :: MountState
                       , ostore_st :: OstoreState
                       }

data FsopState
data MountState
data OstoreState

data VfsInode = VfsInode VfsInodeAbstract FsInode

-- abstract function
vfs_inode_get_ino :: VfsInode -> U32
vfs_inode_get_ino = undefined

data VfsInodeAbstract
data FsInode

type BufOffs = U32

data Buffer = Buffer { buf_data :: WordArray U8, buf_bound :: BufOffs }

type OSPageOffset = U64

bilbyFsBlockShift = 12  :: U32
bilbyFsBlockSize = 4096 :: U32

eNoEnt = 1
eInval = 22

fsop_readpage :: SysState -> FsState -> VfsInode -> OSPageOffset -> Buffer
              -> ((SysState, FsState, VfsInode, Buffer), R_ ErrCode)
fsop_readpage ex fs_st vnode block addr =
  let size = vfs_inode_get_size vnode :: U64
      limit = size `shiftR` fromIntegral bilbyFsBlockShift
   in if | block > limit -> let addr' = buf_memset addr 0 bilbyFsBlockSize 0
                             in ((ex,fs_st,vnode,addr'), Error eNoEnt)
         | block == limit && (size `mod` fromIntegral bilbyFsBlockSize == 0) -> ((ex,fs_st,vnode,addr), Success ())
         | otherwise -> first (\(ex,fs_st,addr) -> (ex,fs_st,vnode,addr)) $ read_block ex fs_st vnode addr block

read_block :: SysState -> FsState -> VfsInode -> Buffer -> OSPageOffset 
           -> ((SysState, FsState, Buffer), R_ ErrCode)
read_block ex fs_st@(FsState _ mount_st ostore_st) vnode buf block =
  let oid = obj_id_data_mk (vfs_inode_get_ino vnode) (downcast block)
      ((ex',ostore_st'), r) = ostore_read ex mount_st ostore_st oid
      fs_st' = fs_st { ostore_st = ostore_st' }
   in case r of
        Error e -> 
          let buf' = if e == eNoEnt then buf_memset buf 0 bilbyFsBlockSize 0 else buf
           in ((ex',fs_st',buf'), Success ())
        Success obj ->
          case extract_data_from_union ex' (ounion obj) of
            Error ex -> absurd undefined
            Success (ex,od) ->
              let size = wordarray_length $ odata od
               in if size > bilbyFsBlockSize then
                    ((ex,fs_st',buf), Error eInval)
                  else let bdata = wordarray_copy (buf_data buf) (odata od) 0 0 size
                           buf' = buf_memset (buf { buf_data = bdata }) size (bilbyFsBlockSize - size) 0
                        in ((ex',fs_st',buf'), Success ())

extract_data_from_union :: SysState -> ObjUnion -> R (SysState, ObjData) SysState 
extract_data_from_union ex u = case u of TObjData v -> Success (ex,v)
                                         _ -> absurd undefined

data Obj = Obj { magic  :: U32
               , crc    :: U32
               , sqnum  :: U64
               , offs   :: U32  -- in-mem only field
               , len    :: U32
               -- , pad1 : U8
               -- , pad2 : U8
               , trans  :: ObjTrans
               , otype  :: ObjType
               , ounion :: ObjUnion
               }

type ObjTrans = U8
type ObjType  = U8
data ObjUnion = TObjDentarr ObjDentarr
              | TObjInode ObjInode
              | TObjData ObjData
              | TObjDel ObjDel
              | TObjSuper ObjSuper
              | TObjSummary ObjSummary
              | TObjPad ()

-- Their definitions shouldn't matter for this example
data ObjDentarr
data ObjInode
data ObjDel
data ObjSuper
data ObjSummary

data ObjData = ObjData { oid :: ObjId, odata :: WordArray U8 }

type ObjId = U64

type VfsIno = U32

obj_id_inode_mk :: VfsIno -> ObjId
obj_id_inode_mk ino = (fromIntegral ino `shiftL` 32) .|. bilbyFsOidMaskInode

obj_id_data_mk :: VfsIno -> U32 -> ObjId
obj_id_data_mk ino blk = obj_id_inode_mk ino .|. bilbyFsOidMaskData .|. fromIntegral blk

bilbyFsOidMaskData :: U64
bilbyFsOidMaskData = fromIntegral bilbyFsObjTypeData `shiftL` fromIntegral bilbyFsXinfoShift

bilbyFsOidMaskInode :: U64
bilbyFsOidMaskInode = fromIntegral bilbyFsObjTypeInode `shiftL` fromIntegral bilbyFsXinfoShift

bilbyFsXinfoShift :: U64
bilbyFsXinfoShift = 29

bilbyFsObjTypeInode :: U8
bilbyFsObjTypeInode = 0

bilbyFsObjTypeData :: U8
bilbyFsObjTypeData = 1


-- TODO: out-of-scope
ostore_read :: SysState -> MountState -> OstoreState -> ObjId -> ((SysState, OstoreState), R Obj ErrCode)
ostore_read = undefined


type VfsSize = U64

-- TODO: abstract function
vfs_inode_get_size :: VfsInode -> VfsSize
vfs_inode_get_size = undefined

buf_memset :: Buffer -> U32 -> U32 -> U8 -> Buffer
buf_memset buf@(Buffer bdata bbound) frm len val = 
  let frm' = if frm < bbound then frm else bbound
      len' = if frm' + len < bbound then len else bbound - frm'
      bdata' = wordarray_set bdata frm' len' val 
   in buf { buf_data = bdata' }

-- abstract datatype
-- NOTE: we assume that the lower bound is always 1
type WordArray a = Array U32 a

type WordArrayIndex = U32

-- TODO: abstract function
wordarray_set :: WordArray a -> U32 -> U32 -> a -> WordArray a
wordarray_set = undefined

-- TODO: abstract function
wordarray_copy :: WordArray a -> WordArray a -> WordArrayIndex -> WordArrayIndex -> U32 -> WordArray a
wordarray_copy dest src dest_off src_off len = undefined

-- abstract function
wordarray_length :: WordArray a -> U32
wordarray_length = snd . bounds 
