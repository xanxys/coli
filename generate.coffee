importScripts 'sylvester.js'

Vector.prototype.to2D=()->
    $V [@e(1),@e(2)]


log=()->
    postMessage
        type: 'debug'
        message: Array.prototype.slice.call arguments


pack_command=(code,args)->
    type: 'command'
    code: code
    arguments: args


pack_comment=(comment)->
    type: 'comment'
    message: comment

pack_block=(label,seq)->
    type: 'block'
    label: label
    sequence: seq


# ps :: [Vec3]
convert_segment=(section_coeff,speed,ps)->
    # FIXME: move this config to somewhere
    epsilon=0.15
    length_coeff=1/section_coeff
    
    if ps.length<2
        pack_block 'null segment',[]
    else
        dist_segment_pt=(p0,p1,q)->
            dq=q.subtract p0
            dp=p1.subtract p0
            
            dp_sq=Math.pow dp.modulus(),2
            dp_dq=Math.pow dq.modulus(),2
            
            t=Math.max(0,Math.min(1,dp_dq/dp_sq))
            dp.multiply(t).distanceFrom(dq)
        
        
        z_base=ps[0].e(3)
        
        seg_init=
            pack_block 'segment start', [
                pack_command "G0", {v:ps[0].add $V([0,0,5])}
                pack_command "G4", {p:500}
                pack_command "G0", {f:50,z:z_base,er:10} # un-reversing
                pack_command "G4", {p:1000}
                pack_command "G0", {f:speed}
                ]
        
        # body generation
        cs=[]
        pt_array=[]
        last_dir=null
        flush=()=>
            first=pt_array[0]
            last=pt_array[pt_array.length-1]
            last_dir=last.subtract(first).toUnitVector()
            
            cs.push pack_command "G1", {v:last,er:last.subtract(first).modulus()*length_coeff}
            pt_array=[last]
        
        for pt in ps
            pt=pt.to2D()
            
            if pt_array.length>=2
                for p in pt_array[1..]
                    if dist_segment_pt(pt_array[0], pt, p)>epsilon
                        flush()
                        break
            
            pt_array.push pt
        
        flush()
        
        seg_body=
            pack_block "segment body", cs
        
        seg_end=
            pack_block 'segment end', [
                pack_command "G0", {er:-10} # reversing
                pack_command "G1", # connect with previous segment
                    v:pt_array[0].add(last_dir.multiply(0.1)) # TODO: parametrize "0.1"s here
                    z:z_base-0.1
                pack_command "G4" # wait for connection to end (unnecessary)
                    p: 1000
                pack_command "G0" # escape
                    z:z_base+8
                ]
        
        pack_block 'segment', [
            seg_init
            seg_body
            seg_end
            ]

            
            

# segments :: [[Vec3]]
# TODO: complete segment rearrangement (but boundary gen must come first)
optimize_segments=(segments)->
    segs=[]
    segs_final=[]
    
    add_segment=(ps)->
        if segs.length==0
            segs=ps
        else
            # flip segs and ps respectively to minimize distance
            d_ff=ps[0].distanceFrom segs[segs.length-1]
            d_ft=ps[ps.length-1].distanceFrom segs[segs.length-1]
            d_tf=ps[0].distanceFrom segs[0]
            d_tt=ps[ps.length-1].distanceFrom segs[0]
            
  #          if segs.length>1
 #               d_tf=1e6
#                d_tt=1e6
            
            d_min=Math.min(d_ff,d_ft,d_tf,d_tt)
            if d_ft==d_min
                ps=ps.reverse()
            else if d_tf==d_min
                segs=segs.reverse()
            else if d_tt==d_min
                segs=segs.reverse()
                ps=ps.reverse()
            
            # move smoothly or jump
            if d_min<3
                segs=segs.concat ps
            else
                segs_final.push segs
                segs=ps
    
    for s in segments
        add_segment s
    
    if segs.length>0
        segs_final.push segs

    segs_final
    


# continuous, volumetric field for configuration
# it will be used to control "macrostructure" such as density, Young's modulus tensor etc.
class DummyConfig
    get_density: (x,y,z)->
        0.5


class BinaryImage
    constructor: (@nx,@ny)->
        @buffer=new ArrayBuffer @nx*@ny # initialized by 0
        @array=new Uint8Array @buffer
    
    # pixel-wise ops
    get: (x,y)->
        @array[x+@nx*y]>0
    
    set: (x,y,v)->
        @array[x+@nx*y]=(if v then 1 else 0)
    
    find: ()->
        for i in [0...@nx*@ny]
            if @array[i]!=0
                return [i%@nx,Math.floor(i/@nx)]
        null

    find_pairs: (excl_int)->
        pairs=[]
        for iy in [0...@ny]
            for ix in [0...@nx]
                if not excl_int.get(ix,iy) and @get(ix,iy)
                    for dy in [-1,0,1]
                        for dx in [-1,0,1]
                            if dx==0 and dy==0
                                continue
                            else
                                if not @get(ix+dx,iy+dy)
                                    pairs.push [[ix,iy],[ix+dx,iy+dy]]       
        pairs
    
    boundaries: ()->
        visited=new BinaryImage @nx, @ny
        
        rotate_ccw=(p,o)->
            $V(p).rotate( Math.PI*0.25,$V(o)).round().elements
            
        rotate_cw=(p,o)->
            $V(p).rotate(-Math.PI*0.25,$V(o)).round().elements
        
        track_loop=(pi,pe)=>
            pts=[]
            check=()->
                pts.push pi
                if visited.get(pi[0],pi[1])
                    return true
                
                if pts.length>10000
                    throw new Error 'too long boundary. maybe a bug'
                
                return false
            
            while true
                # rotate pe CCW
                for i in [1..9]
                    pe_next=rotate_ccw pe, pi
                    if @get(pe_next[0],pe_next[1])
                        break
                    else
                        pe=pe_next
                    
                    if i==9
                        return pts
                
                # rotate pi CW
                while true
                    pi_next=rotate_cw pi, pe
                    if not @get(pi_next[0],pi_next[1])
                        break
                    else
                        
                        if check()
                            return pts
                        else
                            visited.set(pi[0],pi[1],true)
                        
                        pi=pi_next
        
        loops=[]
        log 'loop extraction'
        while true
            # find initial point
            pairs=@find_pairs visited
            if pairs.length==0
                break
            
            log 'iter',pairs.length
            
            [pi,pe]=pairs[0]
            loops.push track_loop(pi,pe)
            
        loops
    
    # 1-ary local op
    copy: ()->
        img=new BinaryImage @nx,@ny
        img.array.set @array
        img
    
    logic_not: ()->
        img=new BinaryImage @nx,@ny
        for i in [0...@nx*@ny]
            img.array[i]=1-@array[i]
        img

    # 2-ary local op
    logic_and: (s)->
        if s.nx!=@nx or s.ny!=@ny
            throw new Error 'size mismatch'
        
        img=new BinaryImage @nx, @ny
        for i in [0...@nx*@ny]
            img.array[i]=s.array[i]&@array[i]
        img
    
    logic_or: (s)->
        if s.nx!=@nx or s.ny!=@ny
            throw new Error 'size mismatch'
        
        img=new BinaryImage @nx, @ny
        for i in [0...@nx*@ny]
            img.array[i]=s.array[i]|@array[i]
        img

    # 1-ary global op
    erode: (w)->
        img=new BinaryImage @nx,@ny
        
        erode_pixel=(ix0,iy0)=>
            for ix in [Math.max(0,ix0-w)..Math.min(@nx-1,ix0+w)]
                for iy in [Math.max(0,iy0-w)..Math.min(@ny-1,iy0+w)]
                    if @array[ix+iy*@nx]==0
                        return
            
            img.array[ix0+iy0*@nx]=1
        
        for iy in [0...@ny]
            for ix in [0...@nx]
                erode_pixel ix, iy
        
        img
    
    dilate: (w)->
        @logic_not().erode(w).logic_not()
    
    fill: (x,y)->
        img=@copy()
        front=[{x:x,y:y}]
        
        while front.length>0
            p=front.pop()
            if p.x<0 or p.y<0 or p.x>=@nx or p.y>=@ny or img.get(p.x,p.y)!=false
                continue
            
            img.set(p.x,p.y,true)
            
            for dp in [{x:p.x-1,y:p.y},{x:p.x+1,y:p.y},{x:p.x,y:p.y-1},{x:p.x,y:p.y+1}]
                front.push dp
        img






# represents 2d slice of a model. provides path generation based on lattice.
class Layer
    constructor: (@p0,@p1,@scale)->
        # enlarge layer size to make sure the outermost region is empty
        @p0=@p0.subtract $V [5,5]
        @p1=@p1.add $V [5,5]
        
        # calculate width and height
        ns=@p1.subtract(@p0).multiply(1/@scale)
        @nx=Math.ceil ns.e(1)
        @ny=Math.ceil ns.e(2)
        @surf=new BinaryImage @nx, @ny
        
        # setup volume config
        @config=new DummyConfig
    
    
    # public
    add_line: (p0,p1)->
        dp=p1.subtract(p0)
        n=Math.ceil(dp.modulus()/@scale)
        
        for i in [0..n]
            t=i/n
            p=p0.add(dp.multiply(t)).subtract(@p0).multiply(1/@scale).round()
            @surf.set p.e(1), p.e(2), true

    to_commands: (section_coeff,offset,speed,lwidth,infill_y=true,infill_rate=1)->

        
        # mark all regions with different tags
        processed=@surf.copy()
        fills=[]
        
        log 'region separation'
        
        while true
            p=processed.logic_not().find()
            log p
            if p==null
                break
            
            l=@surf.copy()
            l=l.fill p[0], p[1]
            processed=processed.logic_or l
            fills.push
                state: null
                region: l.logic_and @surf.logic_not()
        
        fills[0].state=false # empty region
        
        # construct parity table (empty=false, filled=true, unknown=null)
        log 'parity assignment'
        
        p_false=fills[0].region.copy()
        p_true=new BinaryImage @nx, @ny
        
        check_neighbor=(p)=>
            while p[0]>=0
                if p_false.get p[0], p[1]
                    return true
                if p_true.get p[0], p[1]
                    return false
                p[0]-=1
            
            throw new Error 'unexpected non-empty region found'
        
        while true
            null_exist=false
            for f in fills
                if f.state!=null
                    continue
                
                p0=f.region.find()
                if p0==null
                    throw new Error "degenerate region"
                
                nb=check_neighbor p0
                if nb==null
                    null_exist=true
                else
                    f.state=nb
                    if nb
                        p_true=p_true.logic_or f.region
                    else
                        p_false=p_false.logic_or f.region
            
            if not null_exist
                break
        
        # process each region independently      
        rs=[]  
        for f in fills
            if f.state!=true
                continue
            
            rs.push @region_to_command(f.region,section_coeff,offset,speed,lwidth,infill_y,infill_rate)
        rs

    region_to_command: (region,section_coeff,offset,speed,lwidth,infill_y=true,infill_rate=1)->
        l_width=Math.floor(lwidth/@scale)
        half=Math.floor(l_width/2)
        
        segs=[]
        
        to_vec3=(p)=>
            offset.add @p0.add(p.multiply @scale).to3D()
        
        # in-set exterior
        region=region.erode(half).erode(1).dilate(1)

        postMessage
            type: 'layer'
            layer: region
            

        # find all surfaces
        for bnd in region.boundaries()
            segs.push (to_vec3 $V(pt) for pt in bnd)
        
        
        # in-set further
        region=region.erode(half).erode(1).dilate(1)

        postMessage
            type: 'layer'
            layer: region
            
        # generate internal path along axis
        jitter=Math.floor(Math.random()*l_width)
        
        if infill_y
            ix=jitter
            while ix<@nx
                start=null
                for iy in [0...@ny]
                    if region.get(ix,iy)
                        if start==null
                            start=iy
                    else
                        if start!=null
                            y0=start
                            y1=iy
                            if y1>y0+l_width # line aspect ratio > 1
                                segs.push [to_vec3($V([ix,y0])),to_vec3($V([ix,y1]))]
                            start=null
                ix+=l_width
        else
            iy=jitter
            while iy<@ny
                start=null
                for ix in [0...@nx]
                    if region.get(ix,iy)
                        if start==null
                            start=ix
                    else
                        if start!=null
                            x0=start
                            x1=ix
                            if x1>x0+l_width # line aspect ratio > 1
                                segs.push [to_vec3($V([x0,iy])),to_vec3($V([x1,iy]))]
                            start=null
                iy+=l_width
        
        pack_block 'region', (convert_segment section_coeff, speed, s for s in optimize_segments segs)




# tris :: [[[float]]]
# p0,p1 :: Vector
slice_layer=(z,tris,p0,p1)->
    n_ncross=0
    layer=new Layer(p0,p1,0.1)

    add_segment=(tf,tt0,tt1)->
        tf=$V tf
        tt0=$V tt0
        tt1=$V tt1

        t0=(z-tf.e(3)) / (tt0.e(3)-tf.e(3))
        t1=(z-tf.e(3)) / (tt1.e(3)-tf.e(3))

        p0=tt0.subtract(tf).multiply(t0).add(tf)
        p1=tt1.subtract(tf).multiply(t1).add(tf)

        layer.add_line p0.to2D(), p1.to2D()

    for tri in tris
        f0=tri[0][2]<z
        f1=tri[1][2]<z
        f2=tri[2][2]<z

        if (f0 and f1 and f2) or (not f0 and not f1 and not f2)
            n_ncross++
        else if (f0 and not f1 and not f2) or (not f0 and f1 and f2)
            add_segment(tri[0],tri[1],tri[2])
        else if (not f0 and f1 and not f2) or (f0 and not f1 and f2)
            add_segment(tri[1],tri[2],tri[0])
        else if (not f0 and not f1 and f2) or (f0 and f1 and not f2)
            add_segment(tri[2],tri[0],tri[1])
        else
            throw new Error 'impossible happened'
    
    layer

generate_raft=(c0,c1,section_coeff,speed)->
    dx=3
    
    seg=[]
    for i in [0..Math.floor((c1.e(1)-c0.e(1))/dx)]
        line=[
            $V([c0.e(1)+dx*i,c0.e(2),c0.e(3)])
            $V([c0.e(1)+dx*i,c1.e(2),c0.e(3)])
        ]
            
        if i%2==0
            seg=seg.concat line
        else
            seg=seg.concat line.reverse()
    
    pack_block "raft", [convert_segment section_coeff, speed, seg]
    


@onmessage=(ev)->
    # de-serialize model
    model=ev.data.model
    model.pos0=$V(model.pos0)
    model.pos1=$V(model.pos1)
    model.diag=model.pos1.subtract model.pos0
    
    #
    current_offset=$V(ev.data.offset)
    
    layers=[]
    if ev.data.raft
        c0=current_offset.add(model.pos0).subtract($V([5,5,0]))
        c1=current_offset.add(model.pos1).add($V([5,5,0]))
        layers.push generate_raft c0, c1, ev.data.section_coeff, ev.data.speed
        current_offset=current_offset.add($V([0,0,ev.data.layer_thickness]))

    infill_dir=true
    z_scan=model.pos0.e(3)+ev.data.layer_thickness*0.5 # avoid null layer
    layer_no=0
    while z_scan<model.pos1.e(3)
        layer=
            slice_layer z_scan, model.tris, model.pos0.to2D(), model.pos1.to2D()
        
        layers.push pack_block "layer #{layer_no++}",
           layer.to_commands ev.data.section_coeff, current_offset, ev.data.speed, ev.data.lwidth, infill_dir

        current_offset=current_offset.add($V([0,0,ev.data.layer_thickness]))
        z_scan+=ev.data.layer_thickness
        
        infill_dir=not infill_dir
        
        postMessage
            type: 'tick'
            progress: (z_scan-model.pos0.e(3))/(model.pos1.e(3)-model.pos0.e(3))
    
    postMessage
        type: 'finish'
        gcode: pack_block 'print', layers


