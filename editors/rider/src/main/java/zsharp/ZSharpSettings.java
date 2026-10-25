package zsharp;

import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.components.PersistentStateComponent;
import com.intellij.openapi.components.State;
import com.intellij.openapi.components.Storage;
import com.intellij.util.execution.ParametersListUtil;
import org.jetbrains.annotations.NotNull;

import java.util.List;

/** Settings → Tools → Z#: where `zs` is and the arguments that start its language server. */
@State(name = "ZSharpSettings", storages = @Storage("zsharp.xml"))
public final class ZSharpSettings implements PersistentStateComponent<ZSharpSettings.Data> {
  public static final class Data {
    public String path = "";
    public String lspArguments = "lsp";
  }

  private Data data = new Data();

  public static ZSharpSettings getInstance() {
    return ApplicationManager.getApplication().getService(ZSharpSettings.class);
  }

  public String getPath() {
    return data.path == null ? "" : data.path.trim();
  }

  // empty arguments are still `zs lsp`, as in the Zed and VS Code extensions
  public List<String> getLspArguments() {
    List<String> args = ParametersListUtil.parse(data.lspArguments == null ? "" : data.lspArguments);
    return args.isEmpty() ? List.of("lsp") : args;
  }

  @Override
  public @NotNull Data getState() {
    return data;
  }

  @Override
  public void loadState(@NotNull Data state) {
    data = state;
  }
}
