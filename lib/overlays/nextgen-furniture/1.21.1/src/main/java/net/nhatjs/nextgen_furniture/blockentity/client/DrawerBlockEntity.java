package net.nhatjs.nextgen_furniture.blockentity.client;

import net.minecraft.core.BlockPos;
import net.minecraft.core.NonNullList;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ClientGamePacketListener;
import net.minecraft.network.protocol.game.ClientboundBlockEntityDataPacket;
import net.minecraft.world.Container;
import net.minecraft.world.ContainerHelper;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.storage.ValueInput;
import net.minecraft.world.level.storage.ValueOutput;
import net.nhatjs.nextgen_furniture.blockentity.ModBlockEntities;
import org.jetbrains.annotations.Nullable;

public class DrawerBlockEntity extends BlockEntity implements Container {
   private final NonNullList<ItemStack> items = NonNullList.withSize(9, ItemStack.EMPTY);

   public DrawerBlockEntity(BlockPos pos, BlockState blockState) {
      super(ModBlockEntities.DRAWER.get(), pos, blockState);
   }

   public NonNullList<ItemStack> getItems() {
      return this.items;
   }

   public int getContainerSize() {
      return this.items.size();
   }

   public boolean isEmpty() {
      return this.items.stream().allMatch(ItemStack::isEmpty);
   }

   public ItemStack getItem(int i) {
      return (ItemStack)this.items.get(i);
   }

   public ItemStack removeItem(int i, int i1) {
      ItemStack result = ContainerHelper.removeItem(this.items, i, i1);
      if (!result.isEmpty()) {
         this.sync();
      }

      return result;
   }

   public ItemStack removeItemNoUpdate(int i) {
      ItemStack result = ContainerHelper.takeItem(this.items, i);
      this.sync();
      return result;
   }

   public void setItem(int i, ItemStack itemStack) {
      this.items.set(i, itemStack);
      this.sync();
   }

   public boolean stillValid(Player player) {
      return true;
   }

   public void clearContent() {
      this.items.clear();
      this.sync();
   }

   protected void saveAdditional(ValueOutput output) {
      super.saveAdditional(output);
      ContainerHelper.saveAllItems(output, this.items);
   }

   protected void loadAdditional(ValueInput input) {
      super.loadAdditional(input);
      ContainerHelper.loadAllItems(input, this.items);
   }

   private void sync() {
      this.setChanged();
      if (this.level != null) {
         this.getLevel().sendBlockUpdated(this.worldPosition, this.getBlockState(), this.getBlockState(), 3);
      }
   }

   @Nullable
   public Packet<ClientGamePacketListener> getUpdatePacket() {
      return ClientboundBlockEntityDataPacket.create(this);
   }

}
