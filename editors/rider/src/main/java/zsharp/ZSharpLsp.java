package zsharp;

import com.intellij.execution.ExecutionException;
import com.intellij.execution.configurations.GeneralCommandLine;
import com.intellij.execution.configurations.PathEnvironmentVariableUtil;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.platform.lsp.api.LspServerSupportProvider;
import com.intellij.platform.lsp.api.ProjectWideLspServerDescriptor;
import org.jetbrains.annotations.NotNull;

import java.io.File;

/**
 * Starts the `zs lsp` language server for a project when one of its `.zs` files opens.
 * 2026.2 renamed the LSP API (LspServer… to LspClient…) and kept the old names, deprecated; they
 * are used here so the plugin still runs in 2025.2.
 */
public final class ZSharpLsp implements LspServerSupportProvider {
  static boolean isZs(VirtualFile file) {
    return "zs".equals(file.getExtension());
  }

  @Override
  public void fileOpened(@NotNull Project project, @NotNull VirtualFile file, @NotNull LspServerStarter starter) {
    if (isZs(file)) starter.ensureServerStarted(new Descriptor(project));
  }

  private static final class Descriptor extends ProjectWideLspServerDescriptor {
    Descriptor(Project project) {
      super(project, "Z#");
    }

    @Override
    public boolean isSupportedFile(@NotNull VirtualFile file) {
      return isZs(file);
    }

    @Override
    public @NotNull String getLanguageId(@NotNull VirtualFile file) {
      return "zsharp";
    }

    // `zs` from Settings → Tools → Z#, else from PATH (the login shell's, as the IDE reads it)
    @Override
    public @NotNull GeneralCommandLine createCommandLine() throws ExecutionException {
      ZSharpSettings settings = ZSharpSettings.getInstance();
      String path = settings.getPath();
      if (path.isEmpty()) {
        File found = PathEnvironmentVariableUtil.findExecutableInPathOnAnyOS("zs");
        if (found == null) {
          throw new ExecutionException("zs was not found on PATH. Install it (./dev ./test.sh, then "
              + "src/install.sh bin/zs ~/.local/zs) and add it to PATH, or set its path in Settings → Tools → Z#.");
        }
        path = found.getPath();
      }
      GeneralCommandLine command = new GeneralCommandLine(path).withParameters(settings.getLspArguments());
      String base = getProject().getBasePath();
      return base == null ? command : command.withWorkDirectory(base);
    }
  }
}
