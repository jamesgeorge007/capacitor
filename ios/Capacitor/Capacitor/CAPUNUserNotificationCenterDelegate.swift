import UserNotifications

public class CAPUNUserNotificationCenterDelegate : NSObject, UNUserNotificationCenterDelegate  {

  public var bridge: CAPBridge?
  // Local list of notification id -> JSObject for storing options
  // between notification requets
  var notificationRequestLookup = [String:JSObject]()

  public override init(){
    super.init()
    let center = UNUserNotificationCenter.current()
    center.delegate = self
  }

  public func setBridge(bridge: CAPBridge) {
    self.bridge = bridge
  }
  /**
   * Request permissions to send notifications
   */
  public func requestPermissions() {
    // Override point for customization after application launch.
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options:[.badge, .alert, .sound]) { (granted, error) in
      // Enable or disable features based on authorization.
    }

    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  /**
   * Handle delegate willPresent action when the app is in the foreground.
   * This controls how a notification is presented when the app is running, such as
   * whether it should stay silent, display a badge, play a sound, or show an alert.
   */
  public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     willPresent notification: UNNotification,
                                     withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let request = notification.request
    var plugin: CAPPlugin
    var action = "localNotificationReceived"
    var presentationOptions: UNNotificationPresentationOptions = [];

    var notificationData = makeNotificationRequestJSObject(request)
    if (request.trigger?.isKind(of: UNPushNotificationTrigger.self))! {
      plugin = (self.bridge?.getOrLoadPlugin(pluginName: "PushNotifications"))!
      action = "pushNotificationReceived"
      notificationData = makePushNotificationRequestJSObject(request)
      presentationOptions = [
        .badge,
        .sound
      ]
    } else {
      plugin = (self.bridge?.getOrLoadPlugin(pluginName: "LocalNotifications"))!
      presentationOptions = [
        .badge,
        .sound,
        .alert
      ]
    }

    plugin.notifyListeners(action, data: notificationData)

    if let options = notificationRequestLookup[request.identifier] {
      let silent = options["silent"] as? Bool ?? false
      if silent {
        completionHandler(.init(rawValue:0))
        return
      }
    }

    completionHandler(presentationOptions)
  }

  /**
   * Handle didReceive action, called when a notification opens or activates
   * the app based on an action.
   */
  public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     didReceive response: UNNotificationResponse,
                                     withCompletionHandler completionHandler: @escaping () -> Void) {
    completionHandler()

    var data = JSObject()

    // Get the info for the original notification request
    let originalNotificationRequest = response.notification.request

    let actionId = response.actionIdentifier

    // We turn the two default actions (open/dismiss) into generic strings
    if actionId == UNNotificationDefaultActionIdentifier {
      data["actionId"] = "tap"
    } else if actionId == UNNotificationDismissActionIdentifier {
      data["actionId"] = "dismiss"
    } else {
      data["actionId"] = actionId
    }

    // If the type of action was for an input type, get the value
    if let inputType = response as? UNTextInputNotificationResponse {
      data["inputValue"] = inputType.userText
    }

    var plugin: CAPPlugin
    var action = "localNotificationActionPerformed"

    if (originalNotificationRequest.trigger?.isKind(of: UNPushNotificationTrigger.self))! {
      plugin = (self.bridge?.getOrLoadPlugin(pluginName: "PushNotifications"))!
      data["notificationRequest"] = makePushNotificationRequestJSObject(originalNotificationRequest)
      action = "pushNotificationActionPerformed"
    } else {
      data["notificationRequest"] = makeNotificationRequestJSObject(originalNotificationRequest)
      plugin = (self.bridge?.getOrLoadPlugin(pluginName: "LocalNotifications"))!
    }

    plugin.notifyListeners(action, data: data, retainUntilConsumed: true)
  }

  /**
   * Turn a UNNotificationRequest into a JSObject to return back to the client.
   */
  func makeNotificationRequestJSObject(_ request: UNNotificationRequest) -> JSObject {
    return [
      "id": request.identifier
    ]
  }

  /**
   * Turn a UNNotificationRequest into a JSObject to return back to the client.
   */
  func makePushNotificationRequestJSObject(_ request: UNNotificationRequest) -> JSObject {
    let content = request.content
    return [
      "id": request.identifier,
      "title": content.title,
      "subtitle": content.subtitle,
      "body": content.body,
      "badge": content.badge ?? 1,
      "data": content.userInfo,
    ]
  }

}
