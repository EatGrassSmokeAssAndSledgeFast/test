package net.shiroha233.roadweaver.client.config;

import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.ContainerObjectSelectionList;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.narration.NarratableEntry;
import net.minecraft.client.input.MouseButtonEvent;

import java.util.List;
import java.util.function.Consumer;

/**
 * 预设列表组件。
 */
public class PresetListWidget extends ContainerObjectSelectionList<PresetListWidget.Entry> {
    private static final int ROW_HEIGHT = 28;
    private static final float TITLE_SCALE = 1.15F;
    private static final float SUBTITLE_SCALE = 0.85F;

    private final Consumer<PresetEntry> onSelect;
    private boolean renderBackground = true;
    private boolean renderTopAndBottom = true;

    public PresetListWidget(Minecraft minecraft, int width, int height, int top, int bottom, Consumer<PresetEntry> onSelect) {
        super(minecraft, width, height, top, ROW_HEIGHT);
        this.centerListVertically = false;
        this.onSelect = onSelect;
        this.setRenderBackground(false);
        this.setRenderTopAndBottom(false);
    }

    public void addPreset(String id, String name, boolean active) {
        this.addEntry(new PresetEntry(id, name, null, active));
    }

    public void addPreset(String id, String title, String subtitle, boolean active) {
        this.addEntry(new PresetEntry(id, title, subtitle, active));
    }

    public void clearPresets() {
        this.clearEntries();
    }

    @Override
    public int getRowWidth() {
        return this.width - 10;
    }

    @Override
    protected int scrollBarX() {
        return this.getRowLeft() + this.getRowWidth() + 6;
    }

    @Override
    protected void extractListBackground(GuiGraphicsExtractor graphics) {
        if (renderBackground) {
            super.extractListBackground(graphics);
        }
    }

    @Override
    protected void extractListSeparators(GuiGraphicsExtractor graphics) {
        if (renderTopAndBottom) {
            super.extractListSeparators(graphics);
        }
    }

    public void setLeftPos(int left) {
        setX(left);
    }

    public void setRenderBackground(boolean renderBackground) {
        this.renderBackground = renderBackground;
    }

    public void setRenderTopAndBottom(boolean renderTopAndBottom) {
        this.renderTopAndBottom = renderTopAndBottom;
    }

    public class PresetEntry extends Entry {
        private final String id;
        private final String title;
        private final String subtitle;
        private final boolean active;

        public PresetEntry(String id, String title, String subtitle, boolean active) {
            this.id = id;
            this.title = title;
            this.subtitle = subtitle;
            this.active = active;
        }

        public String getId() {
            return id;
        }

        public String getName() {
            return title;
        }

        @Override
        public void extractContent(GuiGraphicsExtractor graphics, int mouseX, int mouseY, boolean hovering, float partialTick) {
            int top = this.getY();
            int left = this.getX();
            int width = PresetListWidget.this.getRowWidth();
            if (active) {
                graphics.fill(left, top, left + width, top + ROW_HEIGHT, 0xFF333333);
                graphics.outline(left, top, width, ROW_HEIGHT, 0xFFFFFFFF);
            } else if (hovering) {
                graphics.fill(left, top, left + width, top + ROW_HEIGHT, 0xFF222222);
            }

            Minecraft minecraft = Minecraft.getInstance();
            int color = active ? 0xFFFFFFFF : 0xFFAAAAAA;
            int textX = left + 4;
            int maxTextWidth = Math.max(10, width - 10);

            String safeTitle = title == null ? "" : title;
            String safeSubtitle = subtitle;
            if (safeSubtitle != null && safeSubtitle.isBlank()) {
                safeSubtitle = null;
            }
            if (safeSubtitle != null && safeTitle.equals(safeSubtitle)) {
                safeSubtitle = null;
            }

            if (safeSubtitle != null) {
                graphics.pose().pushMatrix();
                graphics.pose().translate(textX, top + 4);
                graphics.pose().scale(TITLE_SCALE, TITLE_SCALE);
                String titleCut = minecraft.font.plainSubstrByWidth(safeTitle, (int) (maxTextWidth / TITLE_SCALE));
                graphics.text(minecraft.font, titleCut, 0, 0, color, false);
                graphics.pose().popMatrix();

                graphics.pose().pushMatrix();
                graphics.pose().translate(textX, top + 18);
                graphics.pose().scale(SUBTITLE_SCALE, SUBTITLE_SCALE);
                String subtitleCut = minecraft.font.plainSubstrByWidth(safeSubtitle, (int) (maxTextWidth / SUBTITLE_SCALE));
                graphics.text(minecraft.font, subtitleCut, 0, 0, 0xFFBBBBBB, false);
                graphics.pose().popMatrix();
            } else {
                String titleCut = minecraft.font.plainSubstrByWidth(safeTitle, maxTextWidth);
                graphics.text(minecraft.font, titleCut, textX, top + 10, color, false);
            }
        }

        @Override
        public boolean mouseClicked(MouseButtonEvent event, boolean doubleClick) {
            if (event.button() == 0) {
                onSelect.accept(this);
                return true;
            }
            return super.mouseClicked(event, doubleClick);
        }

        @Override
        public List<? extends GuiEventListener> children() {
            return List.of();
        }

        @Override
        public List<? extends NarratableEntry> narratables() {
            return List.of();
        }
    }

    public abstract static class Entry extends ContainerObjectSelectionList.Entry<Entry> {}
}
