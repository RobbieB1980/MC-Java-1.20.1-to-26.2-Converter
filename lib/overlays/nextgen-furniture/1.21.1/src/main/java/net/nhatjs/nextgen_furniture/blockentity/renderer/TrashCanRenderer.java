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
import net.nhatjs.nextgen_furniture.block.ConsoleBlock;
import net.nhatjs.nextgen_furniture.block.ModBlocks;
import net.nhatjs.nextgen_furniture.blockentity.client.TrashCanBlockEntity;
import org.jspecify.annotations.Nullable;

public class TrashCanRenderer implements BlockEntityRenderer<TrashCanBlockEntity, FurnitureRenderState> {
   public TrashCanRenderer(Context context) {}
   public FurnitureRenderState createRenderState() { return new FurnitureRenderState(); }

   public void extractRenderState(TrashCanBlockEntity entity, FurnitureRenderState state, float partialTick, Vec3 camera, @Nullable CrumblingOverlay breaking) {
      BlockEntityRenderer.super.extractRenderState(entity, state, partialTick, camera, breaking);
      state.state = entity.getBlockState();
      state.yaw = switch ((Direction)state.state.getValue(ConsoleBlock.FACING)) { case SOUTH -> 180; case WEST -> 90; case EAST -> 270; default -> 0; };
   }

   public void submit(FurnitureRenderState state, PoseStack pose, SubmitNodeCollector nodes, CameraRenderState camera) {
      BlockStateModel model = Minecraft.getInstance().getModelManager().getStandaloneModel(
         state.state.getBlock() == ModBlocks.TRASH_CAN_WHITE.get() ? NhatJSNextGenFurnitureModClient.TRASH_CAN_WHITE_EXTRA_ID : NhatJSNextGenFurnitureModClient.TRASH_CAN_BLACK_EXTRA_ID);
      pose.pushPose();
      pose.translate(.5, 0, .5); pose.mulPose(Axis.YP.rotationDegrees(state.yaw)); pose.translate(-.5, 0, -.5);
      for (int rotation = 0; rotation < 4; rotation++) {
         pose.pushPose();
         pose.translate(.5, .4942, .2357); pose.mulPose(Axis.YP.rotationDegrees(rotation * 90)); pose.mulPose(Axis.XP.rotationDegrees(-10)); pose.translate(-.5, -.5, -.5);
         nodes.submitBlockModel(pose, RenderTypes.cutoutMovingBlock(), FurnitureModelCompat.parts(model), new int[0], state.lightCoords, 0, 0);
         pose.popPose();
      }
      pose.popPose();
   }
}
