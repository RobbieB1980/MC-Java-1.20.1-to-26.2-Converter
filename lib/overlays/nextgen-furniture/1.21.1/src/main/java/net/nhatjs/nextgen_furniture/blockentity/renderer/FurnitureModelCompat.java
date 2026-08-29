package net.nhatjs.nextgen_furniture.blockentity.renderer;

import java.util.ArrayList;
import java.util.List;
import net.minecraft.client.renderer.block.dispatch.BlockStateModel;
import net.minecraft.client.renderer.block.dispatch.BlockStateModelPart;
import net.minecraft.util.RandomSource;

public final class FurnitureModelCompat {
   private FurnitureModelCompat() {}

   @SuppressWarnings("deprecation")
   public static List<BlockStateModelPart> parts(BlockStateModel model) {
      List<BlockStateModelPart> parts = new ArrayList<>();
      model.collectParts(RandomSource.create(), parts);
      return parts;
   }
}
