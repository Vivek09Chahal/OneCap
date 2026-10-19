import Foundation

/// Shared four-point spacing scale. App-specific window and column dimensions stay in the app.
public enum DLSSpacing {
  public static let none: CGFloat = 0
  public static let hairline: CGFloat = 1
  public static let xxs: CGFloat = 2
  public static let xs: CGFloat = 4
  public static let sm: CGFloat = 8
  public static let md: CGFloat = 12
  public static let lg: CGFloat = 16
  public static let xl: CGFloat = 20
  public static let xxl: CGFloat = 24
  public static let xxxl: CGFloat = 32
  public static let huge: CGFloat = 48
}

public enum DLSRadius {
  public static let small: CGFloat = 8
  public static let medium: CGFloat = 12
  public static let large: CGFloat = 16
  public static let extraLarge: CGFloat = 24
}

public enum DLSSize {
  public static let iconCompact: CGFloat = 14
  public static let iconSmall: CGFloat = 16
  public static let iconToolbar: CGFloat = 20
  public static let iconMedium: CGFloat = 24
  public static let iconLarge: CGFloat = 32
  public static let avatar: CGFloat = 44
  public static let border: CGFloat = 1
  public static let eyebrowTracking: CGFloat = 2
}
