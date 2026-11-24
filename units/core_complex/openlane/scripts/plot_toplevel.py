lv = pya.LayoutView.current()
lv.max_hier_levels = 1
lv.zoom_fit()
lv.save_image('toplevel.png', 1000, 1000)
