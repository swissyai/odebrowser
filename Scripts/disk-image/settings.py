# dmgbuild settings for Ode's disk image: the app beside an Applications link,
# over the themed background, in a plain icon view with no toolbar or sidebar.
# Defines passed with -D: app (path to Ode.app), background (the TIFF holding
# the 1x and 2x images), volume_icon (an .icns for the mounted volume).
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: hiding the app's extension writes com.apple.FinderInfo on
# the bundle, which `codesign --verify --strict` refuses; Finder hides an app's
# extension without it.

background = defines["background"]
icon = defines.get("volume_icon")

# The background is drawn for a 640 by 420 point window with the icons centred
# at these points; keep them in step with the artwork's arrow.
window_rect = ((240, 160), (640, 420))
icon_locations = {app_name: (170, 230), "Applications": (470, 230)}
icon_size = 128
text_size = 13

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
grid_spacing = 100
