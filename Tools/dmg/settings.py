# dmgbuild settings: a clear drag-to-Applications window. Used by Tools/release.sh.
import os
here = defines["here"]
app = defines["app"]
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
background = os.path.join(here, "background.tiff")
icon = defines["icon"]
icon_size = 112
text_size = 13
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_icon_preview = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_locations = {"Tarn.app": (170, 292), "Applications": (490, 292)}
