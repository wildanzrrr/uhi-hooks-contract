"use client";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function BuySellWidget() {
  return (
    <Card className="w-full h-full">
      <CardHeader className="py-3">
        <CardTitle>Widget Buy and Sell</CardTitle>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="buy" className="w-full">
          <TabsList className="grid grid-cols-2 mb-4">
            <TabsTrigger value="buy">Buy</TabsTrigger>
            <TabsTrigger value="sell">Sell</TabsTrigger>
          </TabsList>
          <TabsContent value="buy">
            <div className="space-y-4">
              <div>
                <Label htmlFor="buyAmount">Amount (ETH)</Label>
                <Input id="buyAmount" placeholder="0.0" type="number" />
              </div>
              <div>
                <Label htmlFor="buyEstimated">Estimated Receive</Label>
                <Input id="buyEstimated" placeholder="0.0" disabled />
              </div>
              <Button className="w-full bg-green-600 hover:bg-green-700">
                Buy Token
              </Button>
            </div>
          </TabsContent>
          <TabsContent value="sell">
            <div className="space-y-4">
              <div>
                <Label htmlFor="sellAmount">Amount (Token)</Label>
                <Input id="sellAmount" placeholder="0.0" type="number" />
              </div>
              <div>
                <Label htmlFor="sellEstimated">Estimated Receive (ETH)</Label>
                <Input id="sellEstimated" placeholder="0.0" disabled />
              </div>
              <Button className="w-full bg-red-600 hover:bg-red-700">
                Sell Token
              </Button>
            </div>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  );
}
