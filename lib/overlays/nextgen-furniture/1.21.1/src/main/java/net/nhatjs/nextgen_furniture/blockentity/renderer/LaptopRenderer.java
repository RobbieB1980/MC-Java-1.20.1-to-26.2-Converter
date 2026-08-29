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
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.nhatjs.nextgen_furniture.NhatJSNextGenFurnitureModClient;
import net.nhatjs.nextgen_furniture.block.LaptopBlock;
import net.nhatjs.nextgen_furniture.blockentity.client.LaptopBlockEntity;
import org.jspecify.annotations.Nullable;

public class LaptopRenderer implements BlockEntityRenderer<LaptopBlockEntity, FurnitureRenderState> {
   public LaptopRenderer(Context context) {}
   public FurnitureRenderState createRenderState() { return new FurnitureRenderState(); }

   public void extractRenderState(LaptopBlockEntity entity, FurnitureRenderState state, float partialTick, Vec3 camera, @Nullable CrumblingOverlay breaking) {
      BlockEntityRenderer.super.extractRenderState(entity, state, partialTick, camera, breaking);
      state.state = entity.getBlockState();
      state.powered = entity.isPowered();
      state.openDeg = Mth.lerp(partialTick, entity.getPrevOpen(), entity.getOpen()) * 110;
      state.yaw = switch ((Direction)state.state.getValue(LaptopBlock.FACING)) { case SOUTH -> 180; case WEST -> 90; case EAST -> 270; default -> 0; };
   }

   public void submit(FurnitureRenderState state, PoseStack pose, SubmitNodeCollector nodes, CameraRenderState camera) {
      pose.pushPose();
      pose.translate(.5, 0, .5); pose.mulPose(Axis.YP.rotationDegrees(state.yaw)); pose.translate(-.5, 0, -.5);
      pose.translate(.1, .04, .735); pose.mulPose(Axis.XP.rotationDegrees(state.openDeg)); pose.translate(-.1, -.04, -.735);
      BlockStateModel screen = Minecraft.getInstance().getModelManager().getStandaloneModel(NhatJSNextGenFurnitureModClient.LAPTOP_SCREEN_ID);
      nodes.submitBlockModel(pose, RenderTypes.cutoutMovingBlock(), FurnitureModelCompat.parts(screen), new int[0], state.lightCoords, 0, 0);
      if (state.powered) {
         BlockStateModel on = Minecraft.getInstance().getModelManager().getStandaloneModel(NhatJSNextGenFurnitureModClient.LAPTOP_SCREEN_ON_ID);
         nodes.submitBlockModel(pose, RenderTypes.cutoutMovingBlock(), FurnitureModelCompat.parts(on), new int[0], 15728880, 0, 0);
      }
      pose.popPose();
   }
}
