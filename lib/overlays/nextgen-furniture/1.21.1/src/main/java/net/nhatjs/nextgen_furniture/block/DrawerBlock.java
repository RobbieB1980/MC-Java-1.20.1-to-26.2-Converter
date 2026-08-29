package net.nhatjs.nextgen_furniture.block;

import com.mojang.serialization.MapCodec;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.network.chat.Component;
import net.minecraft.world.Containers;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.SimpleMenuProvider;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.ChestMenu;
import net.minecraft.world.inventory.MenuType;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.EntityBlock;
import net.minecraft.world.level.block.RenderShape;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.BlockBehaviour.Properties;
import net.minecraft.world.level.block.state.StateDefinition.Builder;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.EnumProperty;
import net.minecraft.world.level.block.state.properties.Property;
import net.minecraft.world.phys.BlockHitResult;
import net.nhatjs.nextgen_furniture.blockentity.client.DrawerBlockEntity;
import org.jetbrains.annotations.Nullable;

public class DrawerBlock extends Block implements EntityBlock {
   public static final EnumProperty<Direction> FACING = BlockStateProperties.HORIZONTAL_FACING;
   public static MapCodec<DrawerBlock> CODEC = simpleCodec(DrawerBlock::new);

   public DrawerBlock(Properties settings) {
      super(settings);
   }

   protected MapCodec<? extends Block> codec() {
      return CODEC;
   }

   @Nullable
   public BlockState getStateForPlacement(BlockPlaceContext ctx) {
      return (BlockState)this.defaultBlockState().setValue(FACING, ctx.getHorizontalDirection().getOpposite());
   }

   protected void createBlockStateDefinition(Builder<Block, BlockState> builder) {
      builder.add(new Property[]{FACING});
   }

   @Nullable
   public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
      return new DrawerBlockEntity(pos, state);
   }

   protected RenderShape getRenderShape(BlockState state) {
      return RenderShape.MODEL;
   }

   public InteractionResult useWithoutItem(BlockState state, Level world, BlockPos pos, Player player, BlockHitResult hit) {
      if (!world.isClientSide() && world.getBlockEntity(pos) instanceof DrawerBlockEntity drawerBlock) {
         player.openMenu(
            new SimpleMenuProvider(
               (syncId, playerInventory, player1) -> new ChestMenu(MenuType.GENERIC_9x1, syncId, playerInventory, drawerBlock, 1),
               Component.translatable("container.nextgen_furniture.drawer")
            )
         );
      }

      return InteractionResult.CONSUME;
   }

   protected void onRemove(BlockState state, Level world, BlockPos pos, BlockState newState, boolean moved) {
      if (state.getBlock() != newState.getBlock()) {
         if (world.getBlockEntity(pos) instanceof DrawerBlockEntity drawerBlock) {
            Containers.dropContents(world, pos, drawerBlock.getItems());
            world.removeBlockEntity(pos);
         }

         super.affectNeighborsAfterRemoval(state, (net.minecraft.server.level.ServerLevel)world, pos, moved);
      }
   }
}
