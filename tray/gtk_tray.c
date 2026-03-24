#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char *beep_bin;
  char *ui_url;
  GtkStatusIcon *icon;
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
  char *cmd = g_strdup_printf("%s --ctl=quit", quoted);
  spawn_cmd(cmd);
  g_free(cmd);
  g_free(quoted);
  gtk_main_quit();
}

static GtkWidget *build_menu(AppCtx *ctx) {
  GtkWidget *menu = gtk_menu_new();
  GtkWidget *open = gtk_menu_item_new_with_label("Open Controls");
  GtkWidget *quit = gtk_menu_item_new_with_label("Quit Beep");
  g_signal_connect(open, "activate", G_CALLBACK(open_controls), ctx);
  g_signal_connect(quit, "activate", G_CALLBACK(quit_beep), ctx);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), open);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
  gtk_widget_show_all(menu);
  return menu;
}

static void on_activate(GtkStatusIcon *status_icon, gpointer user_data) {
  (void)status_icon;
  AppCtx *ctx = (AppCtx *)user_data;
  open_controls(NULL, ctx);
}

static void on_popup(GtkStatusIcon *status_icon, guint button, guint activate_time, gpointer user_data) {
  (void)status_icon;
  GtkWidget *menu = build_menu((AppCtx *)user_data);
  gtk_menu_popup_at_pointer(GTK_MENU(menu), NULL);
  (void)button;
  (void)activate_time;
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);

  AppCtx ctx;
  memset(&ctx, 0, sizeof(ctx));
  ctx.beep_bin = g_strdup((argc > 1 && argv[1][0] != '\0') ? argv[1] : "beep");
  ctx.ui_url = g_strdup((argc > 2 && argv[2][0] != '\0') ? argv[2] : "http://127.0.0.1:48778/");

  GdkPixbuf *robot = gdk_pixbuf_new_from_xpm_data((const char **)robot_xpm);
  ctx.icon = gtk_status_icon_new_from_pixbuf(robot);
  g_object_unref(robot);
  gtk_status_icon_set_tooltip_text(ctx.icon, "beep");
  gtk_status_icon_set_visible(ctx.icon, TRUE);

  g_signal_connect(ctx.icon, "activate", G_CALLBACK(on_activate), &ctx);
  g_signal_connect(ctx.icon, "popup-menu", G_CALLBACK(on_popup), &ctx);

  gtk_main();

  g_free(ctx.beep_bin);
  g_free(ctx.ui_url);
  return 0;
}
