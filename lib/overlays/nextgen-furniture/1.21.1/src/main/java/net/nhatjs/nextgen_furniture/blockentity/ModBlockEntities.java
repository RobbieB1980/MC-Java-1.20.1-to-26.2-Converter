package net.nhatjs.nextgen_furniture.blockentity;

import java.util.function.Supplier;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;
import net.nhatjs.nextgen_furniture.block.ModBlocks;
import net.nhatjs.nextgen_furniture.blockentity.client.ConsoleBlockEntity;
import net.nhatjs.nextgen_furniture.blockentity.client.DrawerBlockEntity;
import net.nhatjs.nextgen_furniture.blockentity.client.LaptopBlockEntity;
import net.nhatjs.nextgen_furniture.blockentity.client.LightBlockEntity;
import net.nhatjs.nextgen_furniture.blockentity.client.TrashCanBlockEntity;

public final class ModBlockEntities {
   public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES = DeferredRegister.create(BuiltInRegistries.BLOCK_ENTITY_TYPE, "nextgen_furniture");
   public static final Supplier<BlockEntityType<LaptopBlockEntity>> LAPTOP = BLOCK_ENTITIES.register(
      "laptop", () -> new BlockEntityType<>(LaptopBlockEntity::new, (Block)ModBlocks.LAPTOP.get())
   );
   public static final Supplier<BlockEntityType<ConsoleBlockEntity>> CONSOLE = BLOCK_ENTITIES.register(
      "console", () -> new BlockEntityType<>(ConsoleBlockEntity::new, (Block)ModBlocks.GAME_CONSOLE.get())
   );
   public static final Supplier<BlockEntityType<TrashCanBlockEntity>> TRASH_CAN = BLOCK_ENTITIES.register(
      "trash_can",
      () -> new BlockEntityType<>(TrashCanBlockEntity::new, (Block)ModBlocks.TRASH_CAN_BLACK.get(), (Block)ModBlocks.TRASH_CAN_WHITE.get())
   );
   public static final Supplier<BlockEntityType<LightBlockEntity>> LIGHT_EXTRA = BLOCK_ENTITIES.register(
      "light_extra", () -> new BlockEntityType<>(LightBlockEntity::new, (Block)ModBlocks.LIGHT_MODERN.get())
   );
   public static final Supplier<BlockEntityType<DrawerBlockEntity>> DRAWER = BLOCK_ENTITIES.register(
      "drawer",
      () -> new BlockEntityType<>(
            DrawerBlockEntity::new,
               (Block)ModBlocks.DRAWER_2_K_M_WOOD_OAK.get(),
               (Block)ModBlocks.DRAWER_2_K_M_WOOD_BIRCH.get(),
               (Block)ModBlocks.DRAWER_3_K_M_WOOD_OAK.get(),
               (Block)ModBlocks.DRAWER_3_K_M_WOOD_BIRCH.get()
         )
   );

   public static void register(IEventBus eventBus) {
      BLOCK_ENTITIES.register(eventBus);
   }
}
