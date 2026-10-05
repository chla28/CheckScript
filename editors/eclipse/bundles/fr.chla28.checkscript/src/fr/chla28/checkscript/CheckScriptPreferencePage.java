package fr.chla28.checkscript;

import org.eclipse.jface.preference.BooleanFieldEditor;
import org.eclipse.jface.preference.ComboFieldEditor;
import org.eclipse.jface.preference.FieldEditorPreferencePage;
import org.eclipse.jface.preference.IntegerFieldEditor;
import org.eclipse.jface.preference.StringFieldEditor;
import org.eclipse.ui.IWorkbench;
import org.eclipse.ui.IWorkbenchPreferencePage;

/** Fenêtre → Préférences → CheckScript. */
public class CheckScriptPreferencePage extends FieldEditorPreferencePage implements IWorkbenchPreferencePage {

	public CheckScriptPreferencePage() {
		super(GRID);
		setPreferenceStore(Activator.getDefault().getPreferenceStore());
		setDescription(Msg.t(
				"Analyse des scripts shell et Python par « check-script lsp ».\n"
						+ "Les changements s'appliquent aux éditeurs ouverts ensuite.",
				"Analysis of shell and Python scripts by \"check-script lsp\".\n"
						+ "Changes apply to editors opened afterwards."));
	}

	@Override
	protected void createFieldEditors() {
		addField(new StringFieldEditor(Prefs.PATH, Msg.t("Exécutable check-script :", "check-script executable:"), getFieldEditorParent()));
		addField(new ComboFieldEditor(Prefs.LANG, Msg.t("Langue :", "Language:"),
				new String[][] { { Msg.t("Environnement", "Environment"), "" }, { "Français", "fr" }, { "English", "en" } },
				getFieldEditorParent()));
		addField(new ComboFieldEditor(Prefs.PROFILE, Msg.t("Profil :", "Profile:"),
				new String[][] { { Msg.t("Celui du projet (.checkscript.yaml)", "The project's (.checkscript.yaml)"), "" }, { "strict", "strict" },
						{ "default", "default" }, { "legacy", "legacy" } },
				getFieldEditorParent()));
		addField(new BooleanFieldEditor(Prefs.ANALYZE_ON_TYPE, Msg.t("Règles intégrées pendant la frappe", "Built-in rules while typing"),
				getFieldEditorParent()));
		IntegerFieldEditor delay = new IntegerFieldEditor(Prefs.TYPING_DELAY, Msg.t("Pause de frappe (ms) :", "Typing pause (ms):"),
				getFieldEditorParent());
		delay.setValidRange(100, 10000);
		addField(delay);
	}

	@Override
	public void init(IWorkbench workbench) {
	}
}
