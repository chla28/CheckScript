package fr.chla28.checkscript;

import java.util.Map;

import org.eclipse.lsp4e.LanguageClientImpl;
import org.eclipse.lsp4j.jsonrpc.services.JsonNotification;
import org.eclipse.swt.widgets.Display;
import org.eclipse.ui.IEditorPart;
import org.eclipse.ui.IWorkbenchWindow;
import org.eclipse.ui.PlatformUI;

/**
 * Client LSP4E qui reçoit en plus la note du script
 * (« checkScript/score ») et l'affiche dans la ligne d'état.
 */
public class CheckScriptLanguageClient extends LanguageClientImpl {

	@JsonNotification("checkScript/score")
	public void score(Map<String, Object> params) {
		Object score = params.get("score");
		Object grade = params.get("grade");
		Object findings = params.get("findings");
		if (!(score instanceof Number n)) {
			return;
		}
		String text = String.format(Msg.t("CheckScript : %.1f/10 (%s), %s problème(s)", "CheckScript: %.1f/10 (%s), %s issue(s)"),
				n.doubleValue(), grade, findings);
		Display display = PlatformUI.isWorkbenchRunning() ? PlatformUI.getWorkbench().getDisplay() : null;
		if (display == null) {
			return;
		}
		display.asyncExec(() -> {
			IWorkbenchWindow w = PlatformUI.getWorkbench().getActiveWorkbenchWindow();
			IEditorPart editor = w == null || w.getActivePage() == null ? null : w.getActivePage().getActiveEditor();
			if (editor != null) {
				editor.getEditorSite().getActionBars().getStatusLineManager().setMessage(text);
			}
		});
	}
}
