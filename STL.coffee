
load_text_stl=(file,complete,error)->
    rd=new FileReader
    
    rd.onload=(e)->
        tokens=(e.target.result.split /\s+/).reverse()
        
        shift_check=(w)->
            t=tokens.pop()
            if t!=w
                throw new Error "expecting '#{w}', found '#{t}'"
        
        shift_vector=()->
            (parseFloat tokens.pop() for i in [1,2,3])
        
        shift_vertex=()->
            shift_check 'vertex'
            shift_vector()
        
        shift_loop=()->
            shift_check 'outer'
            shift_check 'loop'
            vs=(shift_vertex() for i in [1,2,3])
            shift_check 'endloop'
            vs
        
        shift_facet=()->
            shift_check 'facet'
            shift_check 'normal'
            shift_vector()
            vs=shift_loop()
            shift_check 'endfacet'
            vs
        
        shift_solid=()->
            shift_check 'solid'
            solid_id=tokens.pop()
            
            tris=[]
            
            while tokens.length>0
                if tokens[tokens.length-1]=='endsolid'
                    complete tris
                    break
                else
                    tris.push shift_facet()
        
        try
            shift_solid()
        catch e
            error e
    
    rd.readAsText file

load_binary_stl=(file,complete,error)->
    rd=new FileReader
    
    rd.onload=(e)->
        blob=new DataView e.target.result
        
        getVertex=(offset)->
            [blob.getFloat32(offset+0,true),
             blob.getFloat32(offset+4,true),
             blob.getFloat32(offset+8,true)]

        # get number of triangles
        ntris=blob.getUint32(80,true)
        if ntris>1000000
            error 'number of triangle is limited to 1 million'
            return

        # read vertices
        vbuf=new Float32Array(9*ntris)
        
        ofs=84
        tris=
            for i in [0...ntris]
                tri=[]
                tri.push getVertex(ofs+4* 3)
                tri.push getVertex(ofs+4* 6)
                tri.push getVertex(ofs+4* 9)
                ofs+=4*12+2
                tri
        
        complete tris
    
    rd.readAsArrayBuffer file


# retval : [[[float]]] : array of triangles
load_stl=(file,complete,error)->
    load_text_stl file, complete, (e_text)->
        load_binary_stl file, complete, (e_binary)->
            error "STL file is neither binary nor ASCII #{e_text} #{e_binary}"

