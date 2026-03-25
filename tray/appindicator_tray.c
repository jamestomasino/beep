#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

#if defined(USE_AYATANA)
#include <libayatana-appindicator/app-indicator.h>
#elif defined(USE_APPINDICATOR)
#include <libappindicator/app-indicator.h>
#else
#error "Define USE_AYATANA or USE_APPINDICATOR"
#endif

typedef struct {
  char *beep_bin;
  char *ui_url;
  AppIndicator *indicator;
} AppCtx;

static const char *robot_xpm[] = {
  "16 16 4 1",
  " 	c None",
  ".	c #111111",
  "+	c #89D7FF",
  "@	c #E8F4FF",
  "                ",
  "    ........    ",
  "   .++++++++.   ",
  "  .+@@+..+@@+.  ",
  "  .+@@+..+@@+.  ",
  "  .++++++++++.  ",
  "  .+..++++..+.  ",
  "  .+@@@@@@@@+.  ",
  "  .+@++++++@+.  ",
  "  .+@@@@@@@@+.  ",
  "  .++++..++++.  ",
  "   .++++++++.   ",
  "    .........   ",
  "       ..       ",
  "                ",
  "                "
};

static void spawn_cmd(const char *cmd) {
  if (cmd == NULL || cmd[0] == '\0') {
    return;
  }
  g_spawn_command_line_async(cmd, NULL);
}

static char *shell_quote(const char *s) {
  if (s == NULL) {
    return g_strdup("''");
  }
  GString *out = g_string_new("'");
  for (const char *p = s; *p; p++) {
    if (*p == '\'') {
      g_string_append(out, "'\\''");
    } else {
      g_string_append_c(out, *p);
    }
  }
  g_string_append_c(out, '\'');
  return g_string_free(out, FALSE);
}

static void open_controls(GtkMenuItem *item, gpointer user_data) {
  (void)item;
  AppCtx *ctx = (AppCtx *)user_data;
  char *quoted = shell_quote(ctx->ui_url);
  char *cmd = g_strdup_printf("xdg-open %s", quoted);
  spawn_cmd(cmd);
  g_free(cmd);
  g_free(quoted);
}

static void quit_beep(GtkMenuItem *item, gpointer user_data) {
  (void)item;
  AppCtx *ctx = (AppCtx *)user_data;
  char *quoted = shell_quote(ctx->beep_bin);
  char *cmd = g_strdup_printf("env -u LD_LIBRARY_PATH %s --ctl=quit", quoted);
  spawn_cmd(cmd);
  g_free(cmd);
  g_free(quoted);
  gtk_main_quit();
}

static char *prepare_robot_icon(void) {
  GdkPixbuf *robot = gdk_pixbuf_new_from_xpm_data((const char **)robot_xpm);
  if (robot == NULL) {
    return NULL;
  }

  const char *tmp = g_get_tmp_dir();
  char *path = g_build_filename(tmp, "beep-tray-robot.png", NULL);
  GError *err = NULL;
  gdk_pixbuf_save(robot, path, "png", &err, NULL);
  g_object_unref(robot);
  if (err != NULL) {
    g_error_free(err);
    g_free(path);
    return NULL;
  }
  return path;
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);

  AppCtx ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.beep_bin = g_strdup((argc > 1 && argv[1][0] != '\0') ? argv[1] : "beep");
  ctx.ui_url = g_strdup((argc > 2 && argv[2][0] != '\0') ? argv[2] : "http://127.0.0.1:48778/");

  GtkWidget *menu = gtk_menu_new();
  GtkWidget *open = gtk_menu_item_new_with_label("Open Controls");
  GtkWidget *quit = gtk_menu_item_new_with_label("Quit Beep");
  g_signal_connect(open, "activate", G_CALLBACK(open_controls), &ctx);
  g_signal_connect(quit, "activate", G_CALLBACK(quit_beep), &ctx);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), open);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
  gtk_widget_show_all(menu);

  ctx.indicator = app_indicator_new("beep-tray", "computer", APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  app_indicator_set_status(ctx.indicator, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_menu(ctx.indicator, GTK_MENU(menu));

  char *icon_path = prepare_robot_icon();
  if (icon_path != NULL) {
    char *dir = g_path_get_dirname(icon_path);
    app_indicator_set_icon_theme_path(ctx.indicator, dir);
    app_indicator_set_icon_full(ctx.indicator, "beep-tray-robot", "beep");
    g_free(dir);
    g_free(icon_path);
  }

  gtk_main();

  g_free(ctx.beep_bin);
  g_free(ctx.ui_url);
  return 0;
}
