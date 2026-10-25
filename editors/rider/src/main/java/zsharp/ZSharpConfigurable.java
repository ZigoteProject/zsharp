package zsharp;

import com.intellij.openapi.fileChooser.FileChooserDescriptorFactory;
import com.intellij.openapi.options.Configurable;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectManager;
import com.intellij.openapi.ui.TextFieldWithBrowseButton;
import com.intellij.platform.lsp.api.LspServerManager;
import com.intellij.ui.components.JBTextField;
import com.intellij.util.ui.FormBuilder;

import javax.swing.JComponent;

public final class ZSharpConfigurable implements Configurable {
  private TextFieldWithBrowseButton path;
  private JBTextField arguments;

  @Override
  public String getDisplayName() {
    return "Z#";
  }

  @Override
  public JComponent createComponent() {
    path = new TextFieldWithBrowseButton();
    path.addBrowseFolderListener(null, FileChooserDescriptorFactory.createSingleFileNoJarsDescriptor().withTitle("zs"));
    arguments = new JBTextField();
    arguments.getEmptyText().setText("lsp");
    return FormBuilder.createFormBuilder()
        .addLabeledComponent("Path to zs (empty: zs on PATH):", path)
        .addLabeledComponent("Language server arguments:", arguments)
        .addComponentFillVertically(new javax.swing.JPanel(), 0)
        .getPanel();
  }

  @Override
  public boolean isModified() {
    ZSharpSettings.Data d = ZSharpSettings.getInstance().getState();
    return !path.getText().equals(d.path) || !arguments.getText().equals(d.lspArguments);
  }

  @Override
  public void apply() {
    ZSharpSettings.Data d = ZSharpSettings.getInstance().getState();
    d.path = path.getText();
    d.lspArguments = arguments.getText();
    for (Project project : ProjectManager.getInstance().getOpenProjects()) {
      LspServerManager.getInstance(project).stopAndRestartIfNeeded(ZSharpLsp.class);
    }
  }

  @Override
  public void reset() {
    ZSharpSettings.Data d = ZSharpSettings.getInstance().getState();
    path.setText(d.path);
    arguments.setText(d.lspArguments);
  }
}
