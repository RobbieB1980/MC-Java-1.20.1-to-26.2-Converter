package net.nhatjs.nextgen_furniture.entity.client;

import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.syncher.SynchedEntityData.Builder;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Entity.RemovalReason;
import net.minecraft.world.level.Level;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.damagesource.DamageSource;

public class ChairBlockEntity extends Entity {
   public ChairBlockEntity(EntityType<?> entityType, Level level) {
      super(entityType, level);
   }

   protected void defineSynchedData(Builder builder) {
   }

   protected void readAdditionalSaveData(net.minecraft.world.level.storage.ValueInput compoundTag) {
   }

   protected void addAdditionalSaveData(net.minecraft.world.level.storage.ValueOutput compoundTag) {
   }

   protected void removePassenger(Entity passenger) {
      super.removePassenger(passenger);
      if (this.level() instanceof ServerLevel serverLevel) this.kill(serverLevel);
      else this.discard();
   }

   public void tick() {
      super.tick();
      if (!this.level().isClientSide()) {
         BlockPos pos = this.blockPosition();
         if (this.getPassengers().isEmpty() || this.level().isEmptyBlock(pos)) {
            this.discard();
            this.level().updateNeighbourForOutputSignal(pos, this.level().getBlockState(pos).getBlock());
         }
      }
   }

   public void remove(RemovalReason reason) {
      if (!this.level().isClientSide()) {
         if (this.isVehicle()) {
            this.getPassengers().forEach(p -> p.stopRiding());
         }

         this.ejectPassengers();
      }

      super.remove(reason);
   }

   public boolean hurtServer(ServerLevel level, DamageSource source, float amount) {
      return false;
   }
}
