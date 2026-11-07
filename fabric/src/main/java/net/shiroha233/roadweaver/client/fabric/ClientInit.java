package net.shiroha233.roadweaver.client.fabric;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.minecraft.client.KeyMapping;
import net.minecraft.resources.Identifier;
import net.shiroha233.roadweaver.client.map.ClientMapAccessGuard;
import net.shiroha233.roadweaver.client.map.RoadMapScreen;
import net.shiroha233.roadweaver.client.map.data.ClientMapNotes;
import net.shiroha233.roadweaver.client.map.data.MapSnapshotCache;
import net.shiroha233.roadweaver.network.fabric.MapNetworkFabric;
import com.mojang.blaze3d.platform.InputConstants;

/**
 * Fabric 客户端初始化
 */
public class ClientInit implements ClientModInitializer {
    public static KeyMapping OPEN_MAP;

    @Override
    public void onInitializeClient() {
        MapNetworkFabric.registerClientReceivers();
        
        ClientPlayConnectionEvents.JOIN.register((handler, sender, client) -> {
            ClientMapAccessGuard.reset();
            MapSnapshotCache.clearNow();
            ClientMapNotes.onWorldJoin();
        });
        
        ClientPlayConnectionEvents.DISCONNECT.register((handler, client) -> {
            ClientMapAccessGuard.reset();
            MapSnapshotCache.clearNow();
            ClientMapNotes.onWorldLeave();
        });

        OPEN_MAP = KeyMappingHelper.registerKeyMapping(new KeyMapping(
                "key.roadweaver.open_map",
                InputConstants.Type.KEYBOARD,
                InputConstants.KEY_H,
                KeyMapping.Category.register(Identifier.fromNamespaceAndPath("minecraft", "roadweaver"))
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            if (client.player == null) return;
            if (client.gui.screen() instanceof RoadMapScreen) return;
            while (OPEN_MAP.consumeClick()) {
                if (!ClientMapAccessGuard.canOpen(client)) {
                    continue;
                }
                client.gui.setScreen(new RoadMapScreen());
            }
        });
    }
}
