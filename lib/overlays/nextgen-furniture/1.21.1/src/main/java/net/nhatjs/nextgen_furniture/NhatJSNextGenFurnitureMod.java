package net.nhatjs.nextgen_furniture;

import com.mojang.logging.LogUtils;
import net.neoforged.neoforge.client.model.standalone.SimpleUnbakedStandaloneModel;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.config.ModConfig.Type;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;
import net.neoforged.fml.loading.FMLEnvironment;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;
import net.neoforged.neoforge.event.server.ServerStartingEvent;
import net.nhatjs.nextgen_furniture.block.ModBlocks;
import net.nhatjs.nextgen_furniture.blockentity.ModBlockEntities;
import net.nhatjs.nextgen_furniture.entity.ModEntities;
import net.nhatjs.nextgen_furniture.item.ModCreativeModeTabs;
import net.nhatjs.nextgen_furniture.item.ModItems;
import org.slf4j.Logger;

@Mod("nextgen_furniture")
public class NhatJSNextGenFurnitureMod {
   public static final String MOD_ID = "nextgen_furniture";
   public static final Logger LOGGER = LogUtils.getLogger();

   public NhatJSNextGenFurnitureMod(IEventBus modEventBus, ModContainer modContainer) {
      modEventBus.addListener(this::commonSetup);
      NeoForge.EVENT_BUS.register(this);
      ModBlocks.register(modEventBus);
      ModEntities.register(modEventBus);
      ModBlockEntities.register(modEventBus);
      ModCreativeModeTabs.REGISTRY.register(modEventBus);
      ModItems.register(modEventBus);
      if (FMLEnvironment.getDist() == Dist.CLIENT) {
         NhatJSNextGenFurnitureModClient.init(modEventBus);
      }

      modEventBus.addListener(this::addCreative);
      modEventBus.addListener((net.neoforged.neoforge.client.event.ModelEvent.RegisterStandalone e) -> {
         e.register(NhatJSNextGenFurnitureModClient.LAPTOP_SCREEN_ID, SimpleUnbakedStandaloneModel.blockStateModel(NhatJSNextGenFurnitureModClient.LAPTOP_SCREEN));
         e.register(NhatJSNextGenFurnitureModClient.LAPTOP_SCREEN_ON_ID, SimpleUnbakedStandaloneModel.blockStateModel(NhatJSNextGenFurnitureModClient.LAPTOP_SCREEN_ON));
         e.register(NhatJSNextGenFurnitureModClient.GAME_CONSOLE_EXTRA_ID, SimpleUnbakedStandaloneModel.blockStateModel(NhatJSNextGenFurnitureModClient.GAME_CONSOLE_EXTRA));
         e.register(NhatJSNextGenFurnitureModClient.TRASH_CAN_BLACK_EXTRA_ID, SimpleUnbakedStandaloneModel.blockStateModel(NhatJSNextGenFurnitureModClient.TRASH_CAN_BLACK_EXTRA));
         e.register(NhatJSNextGenFurnitureModClient.TRASH_CAN_WHITE_EXTRA_ID, SimpleUnbakedStandaloneModel.blockStateModel(NhatJSNextGenFurnitureModClient.TRASH_CAN_WHITE_EXTRA));
         e.register(NhatJSNextGenFurnitureModClient.LIGHT_MODERN_EXTRA_ID, SimpleUnbakedStandaloneModel.blockStateModel(NhatJSNextGenFurnitureModClient.LIGHT_MODERN_EXTRA));
      });
      modContainer.registerConfig(Type.COMMON, Config.SPEC);
   }

   private void commonSetup(FMLCommonSetupEvent event) {
   }

   private void addCreative(BuildCreativeModeTabContentsEvent event) {
   }

   @SubscribeEvent
   public void onServerStarting(ServerStartingEvent event) {
   }

   @EventBusSubscriber(modid = "nextgen_furniture", value = Dist.CLIENT)
   static class ClientModEvents {
      @SubscribeEvent
      static void onClientSetup(FMLClientSetupEvent event) {
      }
   }
}
