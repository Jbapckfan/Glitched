import Foundation

protocol DeviceManager: AnyObject {
    var supportedMechanics: Set<MechanicType> { get }
    func activate()
    func deactivate()
}
