-- ----------------------
-- This module is created to consume HL7 Lab (ORU) messages 
-- and create Lab test results in the V6 Occupational Health
-- application.
--
-- (c) 2016 Intelex Inc.  All rights reserved
--
-- 12 Nov 2016 Tommy Ng - First iteration
-- ----------------------

BASE_URL = 'http://cloud3.intelex.com/occupationalhealth/api/v2/object/'
USER = 'tommy'
PASSWORD = 'tommy'

function main(Data)
   -- (1) Parse the HL7 message
   local Msg, Name = hl7.parse{vmd = 'example/demo.vmd', data = Data}
   local Out       = hl7.message{vmd = 'example/demo.vmd', name=Name}
   
   -- (2) If message is not Lab, stop
   if Name ~= "Lab" then      
      iguana.logInfo("Message ["..Name.."] was ignored.")
      return
   end   
      
   -- (3) Map information from the incoming to the outgoing message
   Out:mapTree(Msg)
   trace(Out)

   -- (4) Get data from HL7
   local HealthNo = string.trimWS(Out.PATIENT.PID[3][1][1])
   local LabId = string.trimWS(Out.ORDER[1].ORC[2][1])
   --LabId = 7
   --trace (LabId)
   local PanelName = string.trimWS(Out.ORDER[1].ORDER_DETAIL.OBR[4][1])
   --PanelName = 'ABC'
   --trace (PanelName)
   local Observations = Out.ORDER[1].ORDER_DETAIL.OBSERVATION
   --trace (Observations)
      
   -- (5) Retrieve V6 lab test record
   local LabTest = getRecord(
      "OH_LabTestObject", 
      filter.uri.enc("$filter=HR/HealthNumber eq '"..HealthNo.."' and RecordNo eq "..LabId), 
      "$select=Id")
   --trace(LabTest)

   -- (6) If lab test record is not found, stop
   if LabTest.value == nil or table.maxn(LabTest.value) == 0 then
      iguana.logInfo("Lab Test for Health Number ["..
         HealthNo.."] and Lab Id ["..LabId.."] was not found in Intelex OH.")
      return
   end   

   -- (7) Retrieve V6 lab test panel record
   local LabTestPanel = getRecord(
      "OH_LabTestPanelObject", 
      filter.uri.enc("$filter=Name eq '"..PanelName.."'"), 
      "$expand=LabTests($select=Id,Code)&$select=Id")
   trace (LabTestPanel)

   -- (8) If lab test panel record is not found, stop
   if LabTestPanel.value == nil or table.maxn(LabTestPanel.value) == 0 then
      iguana.logInfo("Lab Test Panel ["..PanelName.."] was not found in Intelex OH.")
      return
   end

   -- (9) Loop through all lab tests associated to the test panel
   for i=1,table.maxn(LabTestPanel.value[1].LabTests),1 
   do
      local code = LabTestPanel.value[1].LabTests[i].Code
      trace (code)

      for i=1,#Observations,1
      do
         local obsId = string.trimWS(Observations[i].OBX[3][1])

         if code == obsId then 
            --print ( code..' = '..obsId )
            local LabTestGUID = LabTest.value[1].Id
            local LabTestBindInfo = LabTest.value[1]["@odata.id"]
            local LabTestTypeGUID = LabTestPanel.value[1].LabTests[i].Id
            local LabTestTypeBindInfo = string.trimWS(LabTestPanel.value[1].LabTests[i]["@odata.id"])
            local Value = string.trimWS(Observations[i].OBX[5][1][1])
            local UoM = string.trimWS(Observations[i].OBX[6][2])

            -- (10) Build json message
            local D = '{ "QValue" : '
            ..Value..', "LabTest@odata.bind" : '
            ..'"'..LabTestBindInfo..'"'
            ..', "TestType@odata.bind" : '
            ..'"'..LabTestTypeBindInfo..'"'
            ..', "ResultOption@odata.bind" : '
            ..'"'..BASE_URL..'OH_OHResultTypeObject(dcd51341-3db1-452d-9ff0-02fd8a7d3891)'..'"'

            -- (11) Retrieve V6 UoM record
            local Uom = getRecord(
               "OH_UoMObject", 
               "$filter=Name%20eq%20'"..UoM.."'", 
               "$select=Id,Name")
            --trace (Uom)
            if Uom.value ~= nil and table.maxn(Uom.value) == 1 then
               D = D..', "UoM@odata.bind" : '..'"'..Uom.value[1]["@odata.id"]..'"'
            end
            D = D..'}'
            trace(D) 

            -- (12) Create V6 lab test row record
            local Result = createRecord('OH_LabTestRowObject', D)
            if Result.error then
               iguana.logInfo(Result.error.message)
            end

         end -- if code == obsId then

      end -- for i=1,#Observations,1

   end -- for i=1,table.maxn(LabTestPanel.value[1].LabTests),1

end


function getRecord(Object, Filter, Other)
   
   local GetUrl = BASE_URL..Object..'?'..Filter..'&'..Other
   
   local Response = net.http.get{ url=GetUrl,
   headers={['Content-Type']='application/json'},
   auth={username=USER, password=PASSWORD},
   live=true,
   debug=true}
   
   return json.parse{data=Response}   
end


function createRecord(Object, Body)
   
   local PostUrl = BASE_URL..Object

   local Response = net.http.post{ url=PostUrl,body=Body,
      headers={['Content-Type']='application/json'},
      auth={username=USER, password=PASSWORD},
      live=true,
      debug=true}

   return json.parse{data=Response}
end