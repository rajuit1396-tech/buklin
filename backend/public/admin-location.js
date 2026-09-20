let locationMap,locationPin,saveCustomerLocation;
let locationGeneration=0;
const locationElement=id=>document.getElementById(id);
function setLocationPoint(lat,lng,zoom=false){
  locationElement('locationLat').value=Number(lat).toFixed(7);
  locationElement('locationLng').value=Number(lng).toFixed(7);
  if(!locationPin) locationPin=L.circleMarker([lat,lng],{radius:9,color:'#ff9800',fillOpacity:1}).addTo(locationMap);
  else locationPin.setLatLng([lat,lng]);
  if(zoom) locationMap.setView([lat,lng],17);
  if(!locationElement('locationAddress').value || locationElement('locationAddress').value.startsWith('Pinned work site:'))
    locationElement('locationAddress').value=`Pinned work site: ${Number(lat).toFixed(7)}, ${Number(lng).toFixed(7)}`;
}
function openLocationPicker(initial,onSave){
  locationGeneration++;
  saveCustomerLocation=onSave;
  locationElement('locationForm').reset();
  locationElement('locationError').textContent='';
  locationElement('locateButton').disabled=false;
  locationElement('locationDialog').showModal();
  if(!locationMap){
    locationMap=L.map('locationMap').setView([24.7136,46.6753],6);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{
      maxZoom:19,referrerPolicy:'strict-origin-when-cross-origin',
      attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(locationMap);
    locationMap.on('click',event=>setLocationPoint(event.latlng.lat,event.latlng.lng));
  }
  if(locationPin){locationPin.remove();locationPin=null;}
  if(initial){locationElement('locationAddress').value=initial.site_address;setLocationPoint(initial.site_lat,initial.site_lng,true);}
  else locationMap.setView([24.7136,46.6753],6);
  requestAnimationFrame(()=>locationMap.invalidateSize());
}
for(const id of ['locationLat','locationLng']) locationElement(id).addEventListener('change',()=>{
  const lat=locationElement('locationLat'),lng=locationElement('locationLng');
  if(lat.value!==''&&lng.value!==''&&lat.checkValidity()&&lng.checkValidity()) setLocationPoint(Number(lat.value),Number(lng.value),true);
});
locationElement('cancelLocationButton').addEventListener('click',()=>locationElement('locationDialog').close());
locationElement('locationDialog').addEventListener('close',()=>locationGeneration++);
locationElement('locateButton').addEventListener('click',()=>{
  const generation=locationGeneration;
  const button=locationElement('locateButton');
  if(!navigator.geolocation){locationElement('locationError').textContent='GPS is unavailable. Tap the map or enter coordinates.';return;}
  button.disabled=true;
  navigator.geolocation.getCurrentPosition(position=>{
    if(generation!==locationGeneration)return;
    button.disabled=false;locationElement('locationError').textContent='';
    setLocationPoint(position.coords.latitude,position.coords.longitude,true);
  },()=>{
    if(generation!==locationGeneration)return;
    button.disabled=false;locationElement('locationError').textContent='Could not get GPS. Tap the map or enter coordinates.';
  },{enableHighAccuracy:true,timeout:15000,maximumAge:0});
});
locationElement('locationForm').addEventListener('submit',async event=>{
  event.preventDefault();
  const button=locationElement('saveLocationButton');if(button.disabled)return;
  button.disabled=true;
  locationElement('cancelLocationButton').disabled=true;
  const location={site_lat:Number(locationElement('locationLat').value),site_lng:Number(locationElement('locationLng').value),site_address:locationElement('locationAddress').value.trim()};
  try{await saveCustomerLocation(location);locationElement('locationDialog').close();}
  catch(error){locationElement('locationError').textContent=error.message;}
  finally{button.disabled=false;locationElement('cancelLocationButton').disabled=false;}
});
locationElement('locationDialog').addEventListener('cancel',event=>{
  if(locationElement('saveLocationButton').disabled)event.preventDefault();
});
