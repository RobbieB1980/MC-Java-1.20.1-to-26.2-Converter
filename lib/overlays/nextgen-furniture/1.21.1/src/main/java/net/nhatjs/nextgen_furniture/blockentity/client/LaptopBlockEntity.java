package net.nhatjs.nextgen_furniture.blockentity.client;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup.Provider;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ClientGamePacketListener;
import net.minecraft.network.protocol.game.ClientboundBlockEntityDataPacket;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.ValueInput;
import net.minecraft.world.level.storage.ValueOutput;
import net.nhatjs.nextgen_furniture.block.LaptopBlock;
import net.nhatjs.nextgen_furniture.blockentity.ModBlockEntities;
import org.jetbrains.annotations.Nullable;

public class LaptopBlockEntity extends BlockEntity {
   private float open;
   private float prevOpen;
   private boolean targetOpen;
   private boolean powered;
   private static final float OPEN_MIN = 0.2F;

   public LaptopBlockEntity(BlockPos pos, BlockState state) {
      super(ModBlockEntities.LAPTOP.get(), pos, state);
   }

   public float getOpen() {
      return this.open;
   }

   public float getPrevOpen() {
      return this.prevOpen;
   }

   public boolean isTargetOpen() {
      return this.targetOpen;
   }

   public void setTargetOpen(boolean v) {
      this.targetOpen = v;
      if (!v) {
         this.setPowered(false);
      }

      this.setChanged();
      this.sync();
   }

   public boolean isOpenEnough() {
      return this.open >= 0.2F;
   }

   public boolean isPowered() {
      return this.powered;
   }

   public void setPowered(boolean v) {
      if (this.powered != v) {
         this.powered = v;
         this.setChanged();
         this.sync();
         if (this.level != null && !this.getLevel().isClientSide()) {
            BlockState s = this.getLevel().getBlockState(this.worldPosition);
            if ((Boolean)s.getValue(LaptopBlock.TURN_ON)) {
               this.getLevel().setBlock(this.worldPosition, (BlockState)s.setValue(LaptopBlock.TURN_ON, v), 3);
            }
         }
      }
   }

   public static void tick(Level w, BlockPos p, BlockState s, LaptopBlockEntity be) {
      be.prevOpen = be.open;
      float speed = 0.08F;
      float target = be.targetOpen ? 1.0F : 0.0F;
      if (be.open < target) {
         be.open = Math.min(target, be.open + speed);
      } else if (be.open > target) {
         be.open = Math.max(target, be.open - speed);
      }

      if (!w.isClientSide() && Math.abs(be.open - target) < 0.001) {
         be.sync();
      }
   }

   protected void saveAdditional(ValueOutput output) {
      super.saveAdditional(output);
      output.putFloat("open", this.open);
      output.putFloat("prevOpen", this.prevOpen);
      output.putBoolean("targetOpen", this.targetOpen);
      output.putBoolean("powered", this.powered);
   }

   protected void loadAdditional(ValueInput input) {
      super.loadAdditional(input);
      this.open = input.getFloatOr("open", this.open);
      this.prevOpen = input.getFloatOr("prevOpen", this.open);
      this.targetOpen = input.getBooleanOr("targetOpen", this.targetOpen);
      this.powered = input.getBooleanOr("powered", this.powered);
   }

   private void sync() {
      if (this.level instanceof ServerLevel sw) {
         sw.getChunkSource().blockChanged(this.worldPosition);
         this.getLevel().sendBlockUpdated(this.worldPosition, this.getBlockState(), this.getBlockState(), 3);
      }
   }

   @Nullable
   public Packet<ClientGamePacketListener> getUpdatePacket() {
      return ClientboundBlockEntityDataPacket.create(this);
   }

   public CompoundTag getUpdateTag(Provider registries) {
      return this.saveWithoutMetadata(registries);
   }
}
