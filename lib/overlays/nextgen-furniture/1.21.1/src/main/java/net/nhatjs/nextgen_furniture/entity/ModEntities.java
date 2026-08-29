package net.nhatjs.nextgen_furniture.entity;

import java.util.function.Supplier;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.registries.DeferredRegister;
import net.nhatjs.nextgen_furniture.entity.client.ChairBlockEntity;

public class ModEntities {
   public static final DeferredRegister.Entities ENTITY_TYPES = DeferredRegister.createEntities("nextgen_furniture");
   public static final Supplier<EntityType<ChairBlockEntity>> CHAIR = ENTITY_TYPES.registerEntityType(
      "chair_entity", ChairBlockEntity::new, MobCategory.MISC, builder -> builder.sized(0.5F, 0.7F)
   );
   public static final Supplier<EntityType<ChairBlockEntity>> SOFA = ENTITY_TYPES.registerEntityType(
      "sofa_entity", ChairBlockEntity::new, MobCategory.MISC, builder -> builder.sized(0.5F, 0.55F)
   );

   public static void register(IEventBus eventBus) {
      ENTITY_TYPES.register(eventBus);
   }
}
