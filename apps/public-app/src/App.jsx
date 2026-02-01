import './App.css'
import gatewayImage from './assets/gateway.jpg'

function App() {
  return (
    <div className="app">
      <img src={gatewayImage} alt="Gateway all the things" className="gateway-image" />
      <p className="welcome-text">Welcome to the Envoy community!</p>
    </div>
  )
}

export default App
