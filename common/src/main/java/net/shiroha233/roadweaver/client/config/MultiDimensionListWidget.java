package net.shiroha233.roadweaver.client.config;

import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.ContainerObjectSelectionList;
import net.minecraft.client.gui.components.events.GuiEventListener;
import net.minecraft.client.gui.narration.NarratableEntry;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.resources.Identifier;
import net.minecraft.sounds.SoundEvents;

import java.util.List;
import java.util.Set;

/**
 * 多维度选择列表组件。
 */
public class MultiDimensionListWidget extends ContainerObjectSelectionList<MultiDimensionListWidget.Entry> {
    private static final int ROW_HEIGHT = 20;

    private final Set<Identifier> selectedDimensions;
    private boolean active = true;
    private boolean renderBackground = true;
    private boolean renderTopAndBottom = true;

    public MultiDimensionListWidget(Minecraft minecraft, int width, int height, int top, int bottom, Set<Identifier> selectedDimensions) {
        super(minecraft, width, height, top, ROW_HEIGHT);
        this.centerListVertically = false;
        this.selectedDimensions = selectedDimensions;
        this.setRenderBackground(false);
        this.setRenderTopAndBottom(false);
    }

    public void setActive(boolean active) {
        this.active = active;
    }

    public boolean isActive() {
        return active;
    }

    public void setDimensions(List<Identifier> allDimensions) {
        this.clearEntries();
        for (Identifier dimension : allDimensions) {
            this.addEntry(new Entry(dimension));
        }
    }

    @Override
    public int getRowWidth() {
        return this.width - 20;
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

    public class Entry extends ContainerObjectSelectionList.Entry<Entry> {
        private final Identifier dimensionId;

        public Entry(Identifier dimensionId) {
            this.dimensionId = dimensionId;
        }

        @Override
        public void extractContent(GuiGraphicsExtractor graphics, int mouseX, int mouseY, boolean hovering, float partialTick) {
            int top = this.getY();
            int left = this.getX();
            boolean selected = selectedDimensions.contains(dimensionId);

            graphics.fill(left + 2, top + 2, left + 14, top + 14, 0xFF000000);
            graphics.outline(left + 2, top + 2, 12, 12, 0xFFAAAAAA);
            if (selected) {
                graphics.centeredText(Minecraft.getInstance().font, "x", left + 8, top + 2, 0xFF55FF55);
            }

            graphics.text(Minecraft.getInstance().font, dimensionId.toString(), left + 20, top + 4, 0xFFFFFFFF, false);
        }

        @Override
        public boolean mouseClicked(MouseButtonEvent event, boolean doubleClick) {
            if (!MultiDimensionListWidget.this.isActive()) {
                return false;
            }
            if (event.button() == 0) {
                if (selectedDimensions.contains(dimensionId)) {
                    selectedDimensions.remove(dimensionId);
                } else {
                    selectedDimensions.add(dimensionId);
                }
                Minecraft.getInstance().getSoundManager().play(SimpleSoundInstance.forUI(SoundEvents.UI_BUTTON_CLICK, 1.0F));
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
}
