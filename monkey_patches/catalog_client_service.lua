local CatalogClientService = class()

function CatalogClientService:get_catalog_data(uri)
   return self._sv.catalog[uri]
end

return CatalogClientService
