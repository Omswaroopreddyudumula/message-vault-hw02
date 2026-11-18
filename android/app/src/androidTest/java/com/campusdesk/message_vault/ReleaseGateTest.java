package com.campusdesk.message_vault;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.*;
import org.junit.*;
import org.junit.runner.RunWith;
import java.io.File;
import static org.junit.Assert.*;

/** Drives the installed release APK through Android accessibility, without a Dart test entrypoint. */
@RunWith(AndroidJUnit4.class)
public class ReleaseGateTest {
 UiDevice d; Context c; Bundle args;
 @Before public void setup() throws Exception {
  d=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
  c=InstrumentationRegistry.getInstrumentation().getTargetContext();
  args=InstrumentationRegistry.getArguments();
  Intent launch=c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
  launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); c.startActivity(launch);
 }
 UiObject2 id(String name) { UiObject2 o=d.wait(Until.findObject(By.res(name)),20000); assertNotNull("Missing "+name,o);return o; }
 void click(String name) { id(name).click(); d.waitForIdle(); }
 void text(String name,String value) { UiObject2 o=id(name);if(!"android.widget.EditText".equals(o.getClassName())){o=o.findObject(By.clazz("android.widget.EditText"));}assertNotNull("Editable "+name,o);o.setText(value);d.pressBack();d.waitForIdle(); }
 void sees(String value){assertTrue("Missing text: "+value,d.wait(Until.hasObject(By.textContains(value)),30000));}
 void shot(String name)throws Exception {File dir=new File(c.getExternalFilesDir(null),"screenshots");dir.mkdirs();assertTrue(d.takeScreenshot(new File(dir,name+".png")));}
 void login(String who){text("email",args.getString(who+"Email"));text("password",args.getString("password"));click("auth_submit");id("post_input");}
 void register(String who,String first){click("auth_toggle");text("first_name",first);text("last_name","VaultTest");text("email",args.getString(who+"Email"));text("password",args.getString("password"));click("auth_submit");id("post_input");}
 void post(String value){text("post_input",value);click("post_submit");sees("Message posted.");sees(value);}
 void probe(String name,String screenshot)throws Exception{click("rules_checks");click(name);sees("permission-denied");shot(screenshot);}
 @Test public void releaseFlow() throws Exception {
  id("auth_submit");click("auth_submit");sees("Enter a valid email.");shot("01-validation");
  register("b","Riley");click("profile");sees("student");shot("02-five-field-profile");d.pressBack();
  post("B witness retained "+args.getString("run"));shot("03-create-B");click("sign_out");
  // The screen keeps credentials in the same route only until auth routing disposes it.
  register("a","Om");post("A original "+args.getString("run"));shot("04-create-A");
  click("rules_checks");click("repeat_post");sees("Already saved; no duplicate created.");shot("05-idempotent-retry");
  UiObject2 edit=d.findObject(By.res(java.util.regex.Pattern.compile("edit_.*")));assertNotNull(edit);edit.click();text("edit_input","A edited "+args.getString("run"));click("save_edit");sees("A edited "+args.getString("run"));shot("06-edit");
  probe("probe_foreign_edit","07-wrong-user-edit-denied");probe("probe_foreign_delete","08-wrong-user-delete-denied");probe("probe_forged","09-forged-author-denied");
  UiObject2 del=d.findObject(By.res(java.util.regex.Pattern.compile("delete_.*")));assertNotNull(del);del.click();click("confirm_delete");sees("Message deleted.");sees("B witness retained "+args.getString("run"));shot("10-delete-single");
  post("A survivor "+args.getString("run"));
  click("sign_out");click("signed_out_probe");sees("permission-denied");shot("11-signed-out-read-denied");
  text("email",args.getString("aEmail"));text("password","wrong-password-123");click("auth_submit");sees("Email or password is incorrect.");shot("12-invalid-login");
  login("a");shot("13-login-board");text("post_input","Unsent volatile draft "+args.getString("run"));shot("14-unsent-draft");
 }
 @Test public void restoredSession()throws Exception {id("post_input");sees("A survivor "+args.getString("run"));assertFalse("Draft unexpectedly persisted",d.hasObject(By.textContains("Unsent volatile draft")));shot(args.getString("label","15-restored"));}
 @Test public void afterClearData()throws Exception{id("auth_submit");shot("17-cleared-data-signed-out");login("a");sees("A survivor "+args.getString("run"));shot("18-cloud-survives-clear-data");}
 @Test public void liveWindow()throws Exception{id("post_input");sees("B live "+args.getString("run"));shot("19-live-second-window");}
 @Test public void offlineStart()throws Exception{id("post_input");sees("B witness retained "+args.getString("run"));text("post_input","Offline retry "+args.getString("run"));click("post_submit");sees("same post ID is retained");shot("20-offline-post-error");}
 @Test public void offlineRetry()throws Exception{id("post_input");click("post_submit");sees("Message posted.");sees("Offline retry "+args.getString("run"));shot("21-offline-retry-recovered");}
}
