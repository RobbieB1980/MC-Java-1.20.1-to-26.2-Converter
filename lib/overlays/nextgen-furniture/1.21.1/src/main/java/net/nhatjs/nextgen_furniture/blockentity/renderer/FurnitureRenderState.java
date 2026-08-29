package net.nhatjs.nextgen_furniture.blockentity.renderer;

import net.minecraft.client.renderer.blockentity.state.BlockEntityRenderState;
import net.minecraft.world.level.block.state.BlockState;

public class FurnitureRenderState extends BlockEntityRenderState {
   public BlockState state;
   public float yaw;
   public float pitch;
   public float openDeg;
   public boolean powered;
}
