package zsharp;

import com.intellij.openapi.application.PathManager;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.plugins.textmate.api.TextMateBundleProvider;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/** The VS Code extension's grammar, which the build copies to the plugin's `textmate` folder. */
public final class ZSharpBundle implements TextMateBundleProvider {
  @Override
  public @NotNull List<PluginBundle> getBundles() {
    // the plugin's jar is <plugin>/lib/zsharp-rider.jar
    String jar = PathManager.getJarPathForClass(ZSharpBundle.class);
    if (jar == null) return List.of();
    Path bundle = Path.of(jar).getParent().resolveSibling("textmate");
    return Files.isDirectory(bundle) ? List.of(new PluginBundle("Z#", bundle)) : List.of();
  }
}
