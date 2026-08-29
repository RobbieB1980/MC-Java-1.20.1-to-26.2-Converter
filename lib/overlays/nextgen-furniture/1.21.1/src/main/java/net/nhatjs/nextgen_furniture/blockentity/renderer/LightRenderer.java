package net.nhatjs.nextgen_furniture.blockentity.renderer;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.SubmitNodeCollector;
import net.minecraft.client.renderer.block.dispatch.BlockStateModel;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderer;
import net.minecraft.client.renderer.blockentity.BlockEntityRendererProvider.Context;
import net.minecraft.client.renderer.feature.ModelFeatureRenderer.CrumblingOverlay;
import net.minecraft.client.renderer.rendertype.RenderTypes;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.core.Direction;
import net.minecraft.world.phys.Vec3;
import net.nhatjs.nextgen_furniture.NhatJSNextGenFurnitureModClient;
import net.nhatjs.nextgen_furniture.block.ModernLightBlock;
import net.nhatjs.nextgen_furniture.blockentity.client.LightBlockEntity;
import org.jspecify.annotations.Nullable;

public class LightRenderer implements BlockEntityRenderer<LightBlockEntity, FurnitureRenderState> {
   public LightRenderer(Context context) {}
   public FurnitureRenderState createRenderState() { return new FurnitureRenderState(); }

   public void extractRenderState(LightBlockEntity entity, FurnitureRenderState state, float partialTick, Vec3 camera, @Nullable CrumblingOverlay breaking) {
      BlockEntityRenderer.super.extractRenderState(entity, state, partialTick, camera, breaking);
      state.state = entity.getBlockState();
      state.powered = entity.isPowered();
      Direction facing = (Direction)state.state.getValue(ModernLightBlock.FACING);
      state.yaw = switch (facing) { case SOUTH -> 180; case WEST -> 90; case EAST -> 270; default -> 0; };
      state.pitch = facing == Direction.UP ? 90 : facing == Direction.DOWN ? -90 : 0;
   }

   public void submit(FurnitureRenderState state, PoseStack pose, SubmitNodeCollector nodes, CameraRenderState camera) {
      BlockStateModel model = Minecraft.getInstance().getModelManager().getStandaloneModel(NhatJSNextGenFurnitureModClient.LIGHT_MODERN_EXTRA_ID);
      pose.pushPose();
      pose.translate(.5, .5, .5); pose.mulPose(Axis.XP.rotationDegrees(state.pitch)); pose.mulPose(Axis.YP.rotationDegrees(state.yaw)); pose.translate(-.5, -.5, -.5);
      nodes.submitBlockModel(pose, RenderTypes.cutoutMovingBlock(), FurnitureModelCompat.parts(model), new int[0], state.lightCoords, 0, 0);
      if (state.powered) nodes.submitBlockModel(pose, RenderTypes.cutoutMovingBlock(), FurnitureModelCompat.parts(model), new int[0], 15728880, 0, 0);
      pose.popPose();
   }
}
