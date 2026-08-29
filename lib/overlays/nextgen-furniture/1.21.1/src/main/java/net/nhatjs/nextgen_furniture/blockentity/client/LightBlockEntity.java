package net.nhatjs.nextgen_furniture.blockentity.client;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup.Provider;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ClientGamePacketListener;
import net.minecraft.network.protocol.game.ClientboundBlockEntityDataPacket;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.ValueInput;
import net.minecraft.world.level.storage.ValueOutput;
import net.nhatjs.nextgen_furniture.block.ModernLightBlock;
import net.nhatjs.nextgen_furniture.blockentity.ModBlockEntities;
import org.jetbrains.annotations.Nullable;

public class LightBlockEntity extends BlockEntity {
   private boolean powered;

   public LightBlockEntity(BlockPos pos, BlockState state) {
      super(ModBlockEntities.LIGHT_EXTRA.get(), pos, state);
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
            if ((Boolean)s.getValue(ModernLightBlock.LIT)) {
               this.getLevel().setBlock(this.worldPosition, (BlockState)s.setValue(ModernLightBlock.LIT, v), 3);
            }
         }
      }
   }

   protected void saveAdditional(ValueOutput output) {
      super.saveAdditional(output);
      output.putBoolean("powered", this.powered);
   }

   protected void loadAdditional(ValueInput input) {
      super.loadAdditional(input);
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
