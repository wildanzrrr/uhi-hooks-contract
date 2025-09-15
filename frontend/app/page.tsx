import BuySellWidget from "@/components/buy-sell-widget";
import EventListener from "@/components/event-listener";
import TransactionsHistory from "@/components/transaction-history";

export default function Home() {
  return (
    <div className="font-sans min-h-screen p-4">
      {/* Main grid layout */}
      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4 h-[calc(100vh-2rem)]">
        {/* Left side - Video and Overlay */}
        <div className="lg:col-span-3 grid grid-rows-[1fr_auto] gap-4">
          {/* Streamer Video */}
          <div className="bg-gray-200 rounded-lg relative flex items-center justify-center">
            <div className="text-3xl font-bold text-gray-600">
              Streamer video
            </div>

            {/* Overlay Notification */}
            <div className="absolute top-4 left-1/2 transform -translate-x-1/2 bg-gray-700 text-white py-2 px-4 rounded">
              Overlay Notification
            </div>

            {/* EventListener component for contract events */}
            <EventListener />
          </div>

          {/* Transactions */}
          <div className="bg-gray-200 rounded-lg p-4">
            <TransactionsHistory />
          </div>
        </div>

        {/* Right side - Buy/Sell Widget */}
        <div className="bg-gray-200 rounded-lg p-4">
          <BuySellWidget />
        </div>
      </div>
    </div>
  );
}
