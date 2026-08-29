package net.nhatjs.nextgen_furniture;
import net.minecraft.client.renderer.rendertype.RenderTypes;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderers;
import net.minecraft.client.renderer.entity.EntityRenderers;
import net.minecraft.resources.Identifier;
import net.minecraft.client.renderer.block.dispatch.BlockStateModel;
import net.neoforged.neoforge.client.model.standalone.StandaloneModelKey;
import net.minecraft.world.level.block.Block;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.nhatjs.nextgen_furniture.block.ModBlocks;
import net.nhatjs.nextgen_furniture.blockentity.ModBlockEntities;
import net.nhatjs.nextgen_furniture.blockentity.renderer.ConsoleRenderer;
import net.nhatjs.nextgen_furniture.blockentity.renderer.LaptopRenderer;
import net.nhatjs.nextgen_furniture.blockentity.renderer.LightRenderer;
import net.nhatjs.nextgen_furniture.blockentity.renderer.TrashCanRenderer;
import net.nhatjs.nextgen_furniture.entity.ModEntities;
import net.nhatjs.nextgen_furniture.entity.renderer.ChairRenderer;

public class NhatJSNextGenFurnitureModClient {
   public static final Identifier LAPTOP_SCREEN = Identifier.fromNamespaceAndPath("nextgen_furniture", "extra/laptop_screen");
   public static final Identifier LAPTOP_SCREEN_ON = Identifier.fromNamespaceAndPath("nextgen_furniture", "extra/laptop_screen_on");
   public static final Identifier GAME_CONSOLE_EXTRA = Identifier.fromNamespaceAndPath("nextgen_furniture", "extra/game_console_extra");
   public static final Identifier TRASH_CAN_BLACK_EXTRA = Identifier.fromNamespaceAndPath("nextgen_furniture", "extra/trash_can_black_extra");
   public static final Identifier TRASH_CAN_WHITE_EXTRA = Identifier.fromNamespaceAndPath("nextgen_furniture", "extra/trash_can_white_extra");
   public static final Identifier LIGHT_MODERN_EXTRA = Identifier.fromNamespaceAndPath("nextgen_furniture", "extra/light_modern_extra");
   public static final StandaloneModelKey<BlockStateModel> LAPTOP_SCREEN_ID = new StandaloneModelKey<>(LAPTOP_SCREEN::getPath);
   public static final StandaloneModelKey<BlockStateModel> LAPTOP_SCREEN_ON_ID = new StandaloneModelKey<>(LAPTOP_SCREEN_ON::getPath);
   public static final StandaloneModelKey<BlockStateModel> GAME_CONSOLE_EXTRA_ID = new StandaloneModelKey<>(GAME_CONSOLE_EXTRA::getPath);
   public static final StandaloneModelKey<BlockStateModel> TRASH_CAN_BLACK_EXTRA_ID = new StandaloneModelKey<>(TRASH_CAN_BLACK_EXTRA::getPath);
   public static final StandaloneModelKey<BlockStateModel> TRASH_CAN_WHITE_EXTRA_ID = new StandaloneModelKey<>(TRASH_CAN_WHITE_EXTRA::getPath);
   public static final StandaloneModelKey<BlockStateModel> LIGHT_MODERN_EXTRA_ID = new StandaloneModelKey<>(LIGHT_MODERN_EXTRA::getPath);

   public static void init(IEventBus eventBus) {
      eventBus.addListener(NhatJSNextGenFurnitureModClient::onClientSetup);
   }

   private static void onClientSetup(FMLClientSetupEvent event) {
      event.enqueueWork(() -> {
         EntityRenderers.register(ModEntities.CHAIR.get(), ChairRenderer::new);
         EntityRenderers.register(ModEntities.SOFA.get(), ChairRenderer::new);
         BlockEntityRenderers.register(ModBlockEntities.LAPTOP.get(), LaptopRenderer::new);
         BlockEntityRenderers.register(ModBlockEntities.CONSOLE.get(), ConsoleRenderer::new);
         BlockEntityRenderers.register(ModBlockEntities.TRASH_CAN.get(), TrashCanRenderer::new);
         BlockEntityRenderers.register(ModBlockEntities.LIGHT_EXTRA.get(), LightRenderer::new);
      });
   }
}
